require 'json'
require 'yaml'
require 'digest'
require 'tmpdir'
require 'fileutils'
require 'open3'

workflow = YAML.load_file(File.expand_path('../.github/workflows/packages.yml', __dir__))
command = workflow.fetch('jobs').fetch('build').fetch('steps').find { |step| step['name'] == 'Record successful build checks' }.fetch('run')

Dir.mktmpdir do |root|
  runtime_dir = "#{root}/sources/openvox/packaging/configs/components"
  FileUtils.mkdir_p(["#{root}/dist", runtime_dir])
  manifest_path = "#{root}/dist/build-manifest-ubuntu26.04.json"
  identity = { 'build' => '42001', 'run' => '1234', 'attempt' => '1', 'sources' => { 'openvox' => { 'sha' => 'abc123', 'base' => '9.1.0', 'commits_since_tag' => 2, 'package_version' => '9.1.0+homelab.42001-1+ubuntu26.04' } } }
  File.write(manifest_path, JSON.generate(identity))
  runtime = { 'version' => '20261018.1', 'sha256sum' => 'runtime-checksum' }
  File.write("#{runtime_dir}/puppet-runtime.json", JSON.generate(runtime))
  agent_log = "#{root}/dist/agent-test.log"
  File.write(agent_log, "Other test output\nRuby 3.4; OpenSSL 3.5; ML-DSA passed\n")
  package_name = 'openvox-agent fixture.deb'
  package_content = "package fixture\x00\xff".b
  File.binwrite("#{root}/dist/#{package_name}", package_content)
  env = { 'TARGET' => 'ubuntu26.04' }

  output, status = Open3.capture2e(env, 'bash', '-e', '-c', command, chdir: root)
  raise output unless status.success?
  expected = identity.merge(
    'checks' => { 'agent_package_tests' => 'passed' },
    'runtime_inputs' => { 'agent_runtime' => runtime, 'agent_crypto' => 'Ruby 3.4; OpenSSL 3.5; ML-DSA passed' },
    'sha256' => { package_name => Digest::SHA256.hexdigest(package_content) }
  )
  raise 'Manifest fields or package checksum changed' unless JSON.parse(File.read(manifest_path)) == expected

  ["Tests passed without runtime evidence\n", nil].each do |log|
    File.write(manifest_path, JSON.generate(identity))
    log ? File.write(agent_log, log) : FileUtils.rm_f(agent_log)
    output, status = Open3.capture2e(env, 'bash', '-e', '-c', command, chdir: root)
    raise 'Accepted missing installed-agent runtime evidence' if status.success?
    raise "Unclear runtime failure: #{output}" unless output.include?('Missing installed agent runtime report')
    raise 'Changed manifest after failed checks' unless JSON.parse(File.read(manifest_path)) == identity
  end
end
puts 'Build manifest checks passed'
