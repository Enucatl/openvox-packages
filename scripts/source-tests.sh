#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
export BUNDLE_PATH=${BUNDLE_PATH:-${RUNNER_TEMP:-/tmp}/openvox-packages-bundle}
cd sources/openvox
bundle install --jobs 4
bundle exec rake parallel:spec
cd "$root"
# Maven must never replace the tested fork with a remote SNAPSHOT of the same name.
ruby scripts/configure-build.rb "$root/sources"
cd sources/jvm-ssl-utils
lein test
classpath="$(lein with-profile dev classpath):target/test-classes"
mkdir -p target/test-classes
javac -cp "$classpath" -d target/test-classes test/java/com/puppetlabs/ssl_utils/IssuerSigningTest.java
java -ea -cp "$classpath" com.puppetlabs.ssl_utils.IssuerSigningTest
lein install
cd "$root/sources/openvoxserver-ca"
gem build openvoxserver-ca.gemspec --output "$root/sources/openvoxserver-ca/openvoxserver-ca-source-tests.gem"
BUNDLE_GEMFILE=$PWD/Gemfile bundle install
BUNDLE_GEMFILE=$PWD/Gemfile bundle exec rake spec_random
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
lein gem install --local --ignore-dependencies --no-document "$root/sources/openvoxserver-ca/openvoxserver-ca-source-tests.gem"
lein test :singlethreaded
lein test :multithreaded
BUNDLE_GEMFILE=$PWD/Gemfile bundle exec ruby "$root/scripts/server-specs.rb"
