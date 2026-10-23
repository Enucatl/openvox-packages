#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/target.sh
[[ $TARGET == ubuntu26.04 ]] || { echo 'Build the common server on ubuntu26.04, then repackage for other targets' >&2; exit 1; }
: "${SERVER_VERSION:?full Debian version required}"
: "${AGENT_VERSION:?full Debian version required}"
root=$PWD
build=$(mktemp -d "$root/.server-build.XXXXXX")
trap 'sudo rm -rf "$build"' EXIT
for repo in openvox-server jvm-ssl-utils openvoxserver-ca jruby-openssl; do
  git clone --no-hardlinks "$root/sources/$repo" "$build/$repo"
done
# EZbake requires a clean Git tree; all recipe changes stay in disposable clones.
ruby scripts/configure-build.rb "$build" "$SERVER_VERSION" "$AGENT_VERSION"
cp scripts/build-jruby-openssl.sh "$build/"
printf '\nRUN dnf install -y java-21-openjdk-devel\n' >> "$build/openvox-server/Dockerfile"

docker build -t openvox-packages-server-builder "$build/openvox-server"
docker run --rm -i -v "$build:/build" openvox-packages-server-builder bash -euo pipefail <<'BUILD'
  mkdir -p /root/.lein
  cat > /root/.lein/profiles.clj <<'CLOJURE'
{:user {:mirrors {"central" {:name "central" :url "https://repo.maven.apache.org/maven2/"}}}}
CLOJURE
  git config --system --add safe.directory "*"
  gem install bundler --no-document
  JAVA_HOME_21_X64=/usr/lib/jvm/java-21-openjdk bash /build/build-jruby-openssl.sh /build/jruby-openssl /build/openvox-server/resources/ext/build-scripts/jruby-openssl.gem
  cd /build/openvoxserver-ca
  gem build openvoxserver-ca.gemspec --output /build/openvox-server/resources/ext/build-scripts/openvoxserver-ca.gem
  cd /build/jvm-ssl-utils
  lein install
  cd /build/openvox-server
  git add Dockerfile project.clj resources/ext
  git -c user.name="OpenVox Packages" -c user.email="packages@localhost" commit -m "Apply coordinated package recipe"
  bundle config set without test
  bundle install
  lein install
  COW=base-ubuntu26.04-i386.cow MOCK= GEM_SOURCE=https://rubygems.org EZBAKE_ALLOW_UNREPRODUCIBLE_BUILDS=true EZBAKE_NODEPLOY=true LEIN_PROFILES=ezbake lein with-profile user,ezbake,provided ezbake local-build
BUILD
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
sudo find "$build/package" -path '*/gems/openvoxserver-ca-*' -type d | grep .
sudo find "$build/package" -path '*/gems/jruby-openssl-*/lib/jopenssl.jar' -type f | grep .
mapfile -t jars < <(sudo find "$build/package" -name puppet-server-release.jar -type f)
[[ ${#jars[@]} == 1 ]]
jar tf "${jars[0]}" > "$build/jar-entries.txt"
grep -Fx 'org/bouncycastle/jsse/provider/BouncyCastleJsseProvider.class' "$build/jar-entries.txt"
