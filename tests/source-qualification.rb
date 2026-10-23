require 'json'
require 'yaml'
require 'tmpdir'
require 'fileutils'
require 'open3'

workflow = YAML.load_file(File.expand_path('../.github/workflows/packages.yml', __dir__))
command = workflow.fetch('jobs').fetch('qualify').fetch('steps').find { |step| step['name'] == 'Record successful source verification' }.fetch('run')
Dir.mktmpdir do |root|
  FileUtils.mkdir_p("#{root}/dist")
  build = { 'server' => 'server.deb', 'server_sha256' => 'a' * 64, 'java' => 'Java 25' }
  File.write("#{root}/dist/server-build.json", JSON.generate(build))
  env = { 'SOURCE_KEY' => 'b' * 64, 'GITHUB_RUN_ID' => '100', 'REUSED' => 'false' }
  run = ->(overrides = {}) { Open3.capture2e(env.merge(overrides), 'bash', '-e', '-c', command, chdir: root) }
  output, status = run.call
  raise output unless status.success?
  checks = JSON.parse(File.read("#{root}/dist/source-checks.json"))
  proof = checks.fetch('source_verification')
  raise 'Lost server identity' unless checks.slice(*build.keys) == build
  raise 'Lost source verification identity' unless proof == { 'key' => env['SOURCE_KEY'], 'run' => '100', 'reused' => false }
  raise 'Missing checks' unless checks.fetch('checks').keys.sort == %w[server_package_tests server_recipe source_tests vault_source_tests]
  output, status = run.call('REUSED' => 'true', 'GITHUB_RUN_ID' => '200')
  raise output unless status.success?
  proof = JSON.parse(File.read("#{root}/dist/source-checks.json")).fetch('source_verification')
  raise 'Reuse lost the original run' unless proof.fetch('run') == '100' && proof.fetch('reused')
  before = File.read("#{root}/dist/source-checks.json")
  _, status = run.call('REUSED' => 'true', 'SOURCE_KEY' => 'c' * 64)
  raise 'Accepted mismatched source verification' if status.success?
  raise 'Changed evidence after rejection' unless File.read("#{root}/dist/source-checks.json") == before
  FileUtils.rm("#{root}/dist/source-qualification.json")
  _, status = run.call('REUSED' => 'true')
  raise 'Accepted missing source verification' if status.success?
end
puts 'Source qualification evidence checks passed'
