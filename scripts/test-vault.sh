#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
export BUNDLE_PATH=${BUNDLE_PATH:-${RUNNER_TEMP:-/tmp}/openvox-packages-bundle}
cd sources/vault
# The module's legacy developer bundle pins Puppet 8; these helpers support the fork.
mkdir -p .package-test-gems
cd .package-test-gems
gem fetch puppetlabs_spec_helper --version 8.0.0 --clear-sources --source https://rubygems.org
gem unpack puppetlabs_spec_helper-8.0.0.gem
# shortcut: helper 8 pins legacy syntax, remove when upstream helper supports OpenVox syntax.
ruby -rrubygems/package <<'RUBY'
spec = Gem::Package.new('puppetlabs_spec_helper-8.0.0.gem').spec
raise 'Helper syntax dependency changed' unless spec.dependencies.any? { |dep| dep.name == 'puppet-syntax' }
spec.dependencies.delete_if { |dep| dep.name == 'puppet-syntax' }
spec.add_dependency('puppet-syntax', '~> 7.3')
File.write('puppetlabs_spec_helper-8.0.0/puppetlabs_spec_helper.gemspec', spec.to_ruby)
RUBY
cd ..
export BUNDLE_GEMFILE=$root/tests/Gemfile.vault
bundle install
# shellcheck disable=SC2016
bundle exec ruby -e 'require "puppet"; abort "Wrong Puppet source" unless $LOADED_FEATURES.any? { |path| path.include?("/sources/openvox/lib/puppet.rb") }'
bundle exec rake spec
