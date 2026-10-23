#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
suite=${1:-all}
shard=${2:-all}
[[ $# -le 2 && $suite =~ ^(all|agent|ssl|server)$ && $shard =~ ^(all|ca|jruby|other)$ ]] || { echo 'Usage: source-tests.sh [all|agent|ssl|server [all|ca|jruby|other]]' >&2; exit 2; }
if [[ $suite == all || $suite == server ]]; then
  [[ -f dist/jruby-openssl.gem && -f dist/openvoxserver-ca.gem ]] || { echo 'Run scripts/build-server.sh before server source tests' >&2; exit 1; }
fi
export BUNDLE_PATH=${BUNDLE_PATH:-${RUNNER_TEMP:-/tmp}/openvox-packages-bundle}
if [[ $suite == all || $suite == agent ]]; then
  cd sources/openvox
  bundle install --jobs 4
  bundle exec rake parallel:spec
  cd "$root/sources/openvoxserver-ca"
  BUNDLE_GEMFILE=$PWD/Gemfile bundle install
  BUNDLE_GEMFILE=$PWD/Gemfile bundle exec rake spec_random
  "$root/scripts/test-vault.sh"
  [[ $suite != agent ]] || exit 0
fi
cd "$root"
# Maven must never replace the tested fork with a remote SNAPSHOT of the same name.
ruby scripts/configure-build.rb "$root/sources"
cd sources/jvm-ssl-utils
if [[ $suite == all || $suite == ssl ]]; then
  lein test
  classpath="$(lein with-profile dev classpath):target/test-classes"
  mkdir -p target/test-classes
  javac -cp "$classpath" -d target/test-classes test/java/com/puppetlabs/ssl_utils/IssuerSigningTest.java
  java -ea -cp "$classpath" com.puppetlabs.ssl_utils.IssuerSigningTest
fi
lein install
[[ $suite != ssl ]] || exit 0
cd "$root/sources/openvox-server"
# Tests load Ruby through this submodule path; replace its upstream revision with our snapshot.
rm -rf ruby/puppet
git clone --no-hardlinks "$root/sources/openvox" ruby/puppet
ruby - "$root/sources/openvoxserver-ca" <<'RUBY'
path = 'ruby/puppet/Gemfile'
text = File.read(path)
needle = "gem 'openvoxserver-ca', '~> 3.0', require: false"
raise 'OpenVox CA dependency changed' unless text.include?(needle)
File.write(path, text.sub(needle, "gem 'openvoxserver-ca', path: #{ARGV.fetch(0).dump}, require: false"))
File.write('dev-resources/Gemfile', "source 'https://rubygems.org'\ngem 'openvoxserver-ca', path: #{ARGV.fetch(0).dump}\n")
RUBY
BUNDLE_GEMFILE=$PWD/Gemfile bundle install
./dev-setup
lein gem install --local --ignore-dependencies --no-document "$root/dist/jruby-openssl.gem"
if [[ $shard == all || $shard == other ]]; then
  lein ruby "$root/tests/jruby-openssl.rb"
  lein gem install --no-document test-unit
  lein ruby "$root/sources/jruby-openssl/test/test_x509_mldsa.rb"
  JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} -Djdk.tls.client.SignatureSchemes=mldsa44,mldsa65,mldsa87,rsa_pss_rsae_sha256,rsa_pkcs1_sha256 -Djdk.tls.server.SignatureSchemes=mldsa44,mldsa65,mldsa87,rsa_pss_rsae_sha256,rsa_pkcs1_sha256" lein ruby "$root/sources/jruby-openssl/integration/mldsa_http.rb"
  JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} -Djava.security.properties=$root/sources/openvox-server/resources/ext/java.security.mldsa -Djdk.tls.client.SignatureSchemes=mldsa44,rsa_pss_rsae_sha256,rsa_pkcs1_sha256 -Djdk.tls.server.SignatureSchemes=mldsa44,rsa_pss_rsae_sha256,rsa_pkcs1_sha256" lein ruby "$root/sources/vault/spec/unit/puppet_x/vault_secrets/jruby_context_check.rb"
fi
lein gem install --local --ignore-dependencies --no-document "$root/dist/openvoxserver-ca.gem"
mapfile -t namespaces < <(ruby "$root/scripts/server-test-namespaces.rb" "$shard")
[[ ${#namespaces[@]} -gt 0 ]]
lein test "${namespaces[@]}" :all
if [[ $shard == all || $shard == other ]]; then
  BUNDLE_GEMFILE=$PWD/Gemfile bundle exec ruby "$root/scripts/server-specs.rb"
fi
