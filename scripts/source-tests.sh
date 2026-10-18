#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
export BUNDLE_PATH=${BUNDLE_PATH:-${RUNNER_TEMP:-/tmp}/openvox-packages-bundle}
# Maven must never replace the tested fork with a remote SNAPSHOT of the same name.
ruby - "$root/sources" <<'RUBY'
require 'pathname'
root = Pathname(ARGV.fetch(0))
ssl = root / 'jvm-ssl-utils/project.clj'
text = ssl.read
old = text.match(/\(defproject org.openvoxproject\/ssl-utils "([^"]+)"/)[1]
local = old.delete_suffix('-SNAPSHOT') + '-homelab.source'
ssl.write(text.gsub('"' + old + '"', '"' + local + '"'))
server = root / 'openvox-server/project.clj'
text = server.read
needle = "[org.openvoxproject/ssl-utils \"#{old}\"]"
raise 'SSL dependency changed' unless text.include?(needle)
server.write(text.gsub(needle, "[org.openvoxproject/ssl-utils \"#{local}\"]"))
vault = root / 'vault/Gemfile'
text = vault.read
raise 'Vault Puppet dependency changed' unless text.include?("gems['puppet'] = location_for(puppet_version)")
vault.write(text.sub("gems['puppet'] = location_for(puppet_version)", "gems['openvox'] = location_for(#{('file://' + (root / 'openvox').to_s).dump})"))
RUBY
cd sources/jvm-ssl-utils
lein test
classpath="$(lein with-profile dev classpath):target/test-classes"
mkdir -p target/test-classes
javac -cp "$classpath" -d target/test-classes test/java/com/puppetlabs/ssl_utils/IssuerSigningTest.java
java -ea -cp "$classpath" com.puppetlabs.ssl_utils.IssuerSigningTest
lein install
cd "$root/sources/openvoxserver-ca"
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
lein gem install --local --ignore-dependencies --no-document "$root/sources/openvoxserver-ca/$(cd "$root/sources/openvoxserver-ca" && gem build openvoxserver-ca.gemspec >/dev/null && ls openvoxserver-ca-*.gem)"
lein test :singlethreaded
lein test :multithreaded
# The rake task configures the embedded JRuby and its own Bundler, independently of MRI.
BUNDLE_GEMFILE=$PWD/Gemfile bundle exec ruby -rrake -e 'Bundler.with_unbundled_env { Rake.application.run(["spec"]) }'
cd "$root/sources/vault"
BUNDLE_GEMFILE=$PWD/Gemfile BUNDLE_WITHOUT=system_tests:release_prep bundle install
# shellcheck disable=SC2016
BUNDLE_GEMFILE=$PWD/Gemfile BUNDLE_WITHOUT=system_tests:release_prep bundle exec ruby -e 'require "puppet"; abort "Wrong Puppet source" unless $LOADED_FEATURES.any? { |path| path.include?("/sources/openvox/lib/puppet.rb") }'
BUNDLE_GEMFILE=$PWD/Gemfile BUNDLE_WITHOUT=system_tests:release_prep bundle exec rake spec
