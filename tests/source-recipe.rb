require 'bundler'

ENV['BUNDLE_GEMFILE'] = File.expand_path('Gemfile.vault', __dir__)
definition = Bundler.definition
fork = definition.dependencies.find { |dependency| dependency.name == 'openvox' }
source = File.expand_path('../sources/openvox', __dir__)
spec = fork.source.specs.find { |candidate| candidate.name == 'openvox' }
raise 'Package bundle does not resolve the local fork' unless spec && File.realpath(spec.full_gem_path) == File.realpath(source)

puts 'Source recipe checks passed'
