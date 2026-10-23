#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/target.sh
[[ $TARGET == ubuntu26.04 ]] || { echo 'Build the common server on ubuntu26.04, then repackage for other targets' >&2; exit 1; }
: "${SERVER_VERSION:?full Debian version required}"
: "${AGENT_VERSION:?full Debian version required}"
root=$PWD
mkdir -p dist
build=$(mktemp -d "$root/.server-build.XXXXXX")
trap 'sudo rm -rf "$build"' EXIT
for repo in openvox-server jvm-ssl-utils openvoxserver-ca jruby-openssl; do
  git clone --no-hardlinks "$root/sources/$repo" "$build/$repo"
done
# EZbake requires a clean Git tree; all recipe changes stay in disposable clones.
ruby scripts/configure-build.rb "$build" "$SERVER_VERSION" "$AGENT_VERSION"
bash scripts/build-jruby-openssl.sh "$build/jruby-openssl" "$root/dist/jruby-openssl.gem"
(cd "$build/openvoxserver-ca" && gem build openvoxserver-ca.gemspec --output "$root/dist/openvoxserver-ca.gem")
cp dist/jruby-openssl.gem dist/openvoxserver-ca.gem "$build/openvox-server/resources/ext/build-scripts/"

if [[ -z ${SERVER_BUILDER_IMAGE:-} ]]; then
  docker build -t openvox-packages-server-builder "$build/openvox-server"
  SERVER_BUILDER_IMAGE=openvox-packages-server-builder
fi
builder_bundle=${RUNNER_TEMP:-/tmp}/openvox-packages-builder-bundle
mkdir -p "$HOME/.m2" "$builder_bundle"
docker run --rm --userns=host -v "$build:/build" -v "$HOME/.m2:/root/.m2" -v "$builder_bundle:/bundle" -e BUNDLE_PATH=/bundle "$SERVER_BUILDER_IMAGE" bash -euo pipefail -c "$(cat <<'BUILD'
  mkdir -p /root/.lein
  cat > /root/.lein/profiles.clj <<'CLOJURE'
{:user {:mirrors {"central" {:name "central" :url "https://repo.maven.apache.org/maven2/"}}}
 ;; Keep the override when Leiningen strips non-leaky profiles for JAR creation.
 :package ^:leaky {:classifiers ^:replace []}}
CLOJURE
  git config --system --add safe.directory "*"
  gem install bundler --no-document
  cd /build/jvm-ssl-utils
  lein install
  cd /build/openvox-server
  git add project.clj resources/ext
  git -c user.name="OpenVox Packages" -c user.email="packages@localhost" commit -m "Apply coordinated package recipe"
  bundle config set without test
  bundle install
  lein with-profile +package install
  COW=base-ubuntu26.04-i386.cow MOCK= GEM_SOURCE=https://rubygems.org EZBAKE_ALLOW_UNREPRODUCIBLE_BUILDS=true EZBAKE_NODEPLOY=true LEIN_PROFILES=ezbake,package lein with-profile user,ezbake,provided,package ezbake local-build
BUILD
)"
mapfile -t packages < <(find "$build/openvox-server/output" -name '*.deb' -type f)
[[ ${#packages[@]} == 1 ]]
[[ -z $(find "$build/openvox-server/target" -name '*-test.jar' -type f -print -quit) ]]
project_version=$(ruby -e 'puts File.read(ARGV.fetch(0)).match(/\(defproject org.openvoxproject\/puppetserver "([^"]+)"/)[1]' "$build/openvox-server/project.clj")
package="dist/openvox-server_${SERVER_VERSION}_all.deb"
ruby scripts/repackage-server.rb "${packages[0]}" "$package" "$SERVER_VERSION" "$AGENT_VERSION" "$project_version-1+ubuntu26.04"
[[ $(dpkg-deb -f "$package" Version) == "$SERVER_VERSION" ]]
dpkg-deb -f "$package" Depends | grep -F "openvox-agent (= $AGENT_VERSION)"
dpkg-deb --fsys-tarfile "$package" | tar -tf - > "$build/package-entries.txt"
grep -Fx './opt/puppetlabs/server/data/puppetserver/java.security.mldsa' "$build/package-entries.txt"
grep -E '/gems/openvoxserver-ca-[^/]+/$' "$build/package-entries.txt"
grep -E '/gems/jruby-openssl-[^/]+/lib/jopenssl.jar$' "$build/package-entries.txt"
mapfile -t jars < <(grep -E '(^|/)puppet-server-release.jar$' "$build/package-entries.txt")
[[ ${#jars[@]} == 1 ]]
dpkg-deb --fsys-tarfile "$package" | tar -xOf - "${jars[0]}" > "$build/puppet-server-release.jar"
jar tf "$build/puppet-server-release.jar" > "$build/jar-entries.txt"
grep -Fx 'org/bouncycastle/jsse/provider/BouncyCastleJsseProvider.class' "$build/jar-entries.txt"
