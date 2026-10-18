#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SERVER_VERSION:?full Debian version required}"
: "${AGENT_VERSION:?full Debian version required}"
root=$PWD
build=$(mktemp -d "$root/.server-build.XXXXXX")
trap 'sudo rm -rf "$build"' EXIT
for repo in openvox-server jvm-ssl-utils openvoxserver-ca; do
  git clone --no-hardlinks "$root/sources/$repo" "$build/$repo"
done
# EZbake requires a clean Git tree; all recipe changes stay in disposable clones.
ruby - "$build" "$SERVER_VERSION" "$AGENT_VERSION" <<'RUBY'
require 'pathname'
root, version, agent = ARGV
server = Pathname(root) / 'openvox-server'
ssl = Pathname(root) / 'jvm-ssl-utils/project.clj'
ssl_text = ssl.read
old = ssl_text.match(/\(defproject org.openvoxproject\/ssl-utils "([^"]+)"/)[1]
local = old.delete_suffix('-SNAPSHOT') + '-homelab.' + version.split('+homelab.').fetch(1).split('-').first
ssl.write(ssl_text.gsub('"' + old + '"', '"' + local + '"'))
dockerfile = server / 'Dockerfile'
raise 'Unexpected builder Java version' unless dockerfile.read.include?('java-21-openjdk-headless')
dockerfile.write(dockerfile.read.sub('java-21-openjdk-headless', 'java-25-openjdk-headless'))
project = server / 'project.clj'
text = project.read
server_old = text.match(/\(defproject org.openvoxproject\/puppetserver "([^"]+)"/)[1]
server_local = server_old.delete_suffix('-SNAPSHOT') + '-homelab.' + version.split('+homelab.').fetch(1).split('-').first
raise 'EZbake self dependency changed' unless text.scan('[org.openvoxproject/puppetserver "' + server_old + '"]').size == 2
text = text.gsub('"' + server_old + '"', '"' + server_local + '"')
needle = "[org.openvoxproject/ssl-utils \"#{old}\"]"
raise 'SSL dependency changed' unless text.include?(needle)
text = text.gsub(needle, "[org.openvoxproject/ssl-utils \"#{local}\"]")
needle = ':resources {:dir "tmp/ezbake-resources"}'
raise 'EZbake project config changed' unless text.include?(needle)
text = text.sub(needle, ':project-files [{:file "resources/ext/java.security.mldsa" :install {:path "/opt/puppetlabs/server/data/puppetserver"}}] ' + needle)
project.write(text)
config = server / 'resources/ext/ezbake.conf'
text = config.read
raise 'Agent dependency changed' unless text.include?('openvox-agent (>= 9.1.0)')
config.write(text.gsub('openvox-agent (>= 9.1.0)', "openvox-agent (= #{agent})"))
gem_list = server / 'resources/ext/build-scripts/mri-gem-list-no-dependencies.txt'
raise 'CA gem list changed' unless gem_list.read.strip.match?(/\Aopenvoxserver-ca \S+\z/)
gem_list.write('')
installer = server / 'resources/ext/build-scripts/install-vendored-gems.sh'
installer.write(installer.read + <<~'INSTALL')

  # Install the coordinated fork without resolving the public gem of the same version.
  gem_install_jars=(ext/classpath-jars/{bcpkix,bcprov}-jdk18on-*.jar)
  java -cp "$(IFS=:; echo "${gem_install_jars[*]}"):puppet-server-release.jar" clojure.main -m puppetlabs.puppetserver.cli.gem --config jruby.conf -- install --local --ignore-dependencies --no-document ext/build-scripts/openvoxserver-ca-*.gem
INSTALL
RUBY
docker build -t openvox-packages-server-builder "$build/openvox-server"
docker run --rm -v "$build:/build" openvox-packages-server-builder bash -euo pipefail -c '
  git config --global --add safe.directory "*"
  gem install bundler --no-document
  cd /build/openvoxserver-ca
  gem build openvoxserver-ca.gemspec
  cp openvoxserver-ca-*.gem /build/openvox-server/resources/ext/build-scripts/
  cd /build/jvm-ssl-utils
  lein install
  cd /build/openvox-server
  git add project.clj resources/ext
  git -c user.name="OpenVox Packages" -c user.email="packages@localhost" commit -m "Apply coordinated package recipe"
  bundle config set without test
  bundle install
  lein install
  COW=base-ubuntu26.04-i386.cow MOCK= GEM_SOURCE=https://rubygems.org EZBAKE_ALLOW_UNREPRODUCIBLE_BUILDS=true EZBAKE_NODEPLOY=true LEIN_PROFILES=ezbake lein with-profile user,ezbake,provided ezbake local-build
'
mapfile -t packages < <(find "$build/openvox-server/output" -name '*.deb' -type f)
[[ ${#packages[@]} == 1 ]]
# Preserve EZbake's maintainer scripts and payload while assigning the archive version.
sudo dpkg-deb --raw-extract "${packages[0]}" "$build/package"
sudo ruby - "$build/package/DEBIAN/control" "$SERVER_VERSION" <<'RUBY'
path, version = ARGV
text = File.read(path)
raise 'Missing or duplicate package version' unless text.scan(/^Version: .+$/).size == 1
File.write(path, text.sub(/^Version: .+$/, 'Version: ' + version))
RUBY
mkdir -p dist
package="dist/openvox-server_${SERVER_VERSION}_all.deb"
sudo dpkg-deb --build "$build/package" "$package"
[[ $(dpkg-deb -f "$package" Version) == "$SERVER_VERSION" ]]
dpkg-deb -f "$package" Depends | grep -F "openvox-agent (= $AGENT_VERSION)"
[[ -f "$build/package/opt/puppetlabs/server/data/puppetserver/java.security.mldsa" ]]
find "$build/package" -path '*/gems/openvoxserver-ca-*' -type d | grep .
mapfile -t jars < <(find "$build/package" -name puppet-server-release.jar -type f)
[[ ${#jars[@]} == 1 ]]
jar tf "${jars[0]}" > "$build/jar-entries.txt"
grep -Fx 'org/bouncycastle/jsse/provider/BouncyCastleJsseProvider.class' "$build/jar-entries.txt"
