require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'fileutils'

script = File.expand_path('../scripts/server-test-namespaces.rb', __dir__)
sources = File.expand_path('../sources/openvox-server', __dir__)
run = lambda do |shard, directory = sources|
  output, error, status = Open3.capture3(RbConfig.ruby, script, shard, chdir: directory)
  raise error unless status.success?
  output.lines.map(&:strip)
end
all = run.call('all')
parts = %w[ca jruby other].to_h { |shard| [shard, run.call(shard)] }
raise 'Empty server test shard' if parts.values.any?(&:empty?)
raise 'Missing or repeated test namespaces' unless parts.values.flatten.sort == all.sort
raise 'CA tests missing' unless parts['ca'].include?('puppetlabs.puppetserver.certificate-authority-mldsa-test')
raise 'Threading tests missing' unless parts['jruby'].include?('puppetlabs.services.jruby.jruby-puppet-pool-int-test')

Dir.mktmpdir do |root|
  FileUtils.mkdir_p("#{root}/test/unit")
  File.write("#{root}/test/unit/new_test.clj", '(ns new-test)')
  raise 'New test namespace lost' unless run.call('other', root) == ['new-test']
  File.write("#{root}/test/unit/broken.clj", 'no namespace')
  _, _, status = Open3.capture3(RbConfig.ruby, script, 'all', chdir: root)
  raise 'Malformed namespace accepted' if status.success?
end
_, _, status = Open3.capture3(RbConfig.ruby, script, 'invalid', chdir: sources)
raise 'Invalid shard accepted' if status.success?
puts "Server test shards cover #{all.size} namespaces exactly once"
