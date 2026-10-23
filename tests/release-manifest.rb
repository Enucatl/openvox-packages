require 'json'
require 'digest'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'

scripts = File.expand_path('../scripts', __dir__)
targets = %w[ubuntu26.04 ubuntu24.04 debian13]
Dir.mktmpdir do |root|
  FileUtils.mkdir_p("#{root}/dist")
  FileUtils.cp_r(scripts, "#{root}/scripts")
  write = ->(name, data) { File.write("#{root}/dist/#{name}.json", JSON.pretty_generate(data) + "\n") }
  read = ->(name) { JSON.parse(File.read("#{root}/dist/#{name}.json")) }
  run = ->(script, env = {}) { Open3.capture3(env, RbConfig.ruby, "scripts/#{script}.rb", chdir: root) }
  source = {
    'build' => '42001', 'run' => '42', 'attempt' => '1',
    'sources' => %w[openvox openvox-server jvm-ssl-utils openvoxserver-ca jruby-openssl vault].to_h { |repo| [repo, { 'sha' => 'a' * 40 }] }
  }
  source['sources']['openvox']['package_version'] = '9.1.0+homelab.42001-1+ubuntu26.04'
  source['sources']['openvox-server']['package_version'] = '9.1.1+homelab.42001-1+ubuntu26.04'
  write.call('build-manifest', source)
  targets.each do |target|
    env_file = "#{root}/github-env"
    File.write(env_file, '')
    _, error, status = run.call('select-target', 'TARGET' => target, 'GITHUB_ENV' => env_file)
    raise error unless status.success?
    selected = read.call("build-manifest-#{target}")
    raise 'Target identity changed' unless selected['target'] == target && selected.reject { |key, _| %w[target sources].include?(key) } == source.reject { |key, _| key == 'sources' }
    source['sources'].each do |repo, data|
      expected = data.transform_values { |value| value.sub('ubuntu26.04', target) }
      raise 'Target snapshot changed' unless selected['sources'][repo] == expected
    end
    raise 'Missing target version environment' unless File.read(env_file).include?("AGENT_VERSION=9.1.0+homelab.42001-1+#{target}\n") && File.read(env_file).include?("BUILD_NUMBER=42001\n")
    agent_file = "openvox-agent_#{selected['sources']['openvox']['package_version']}_amd64.deb"
    File.write("#{root}/dist/#{agent_file}", "tested agent fixture #{target}")
    selected['checks'] = { 'agent_package_tests' => 'passed' }
    selected['runtime_inputs'] = { 'agent_crypto' => "#{target} crypto fixture" }
    selected['sha256'] = { agent_file => Digest::SHA256.file("#{root}/dist/#{agent_file}").hexdigest }
    write.call("build-manifest-#{target}", selected)
  end
  _, _, status = run.call('select-target', 'TARGET' => 'debian12', 'GITHUB_ENV' => "#{root}/github-env")
  raise 'Accepted unsupported target' if status.success?
  invalid = Marshal.load(Marshal.dump(source))
  invalid['sources']['openvox']['package_version'] = '9.1.0+homelab.42001-1+debian13'
  write.call('build-manifest', invalid)
  _, _, status = run.call('select-target', 'TARGET' => 'ubuntu24.04', 'GITHUB_ENV' => "#{root}/github-env")
  raise 'Accepted a noncanonical source snapshot' if status.success?
  write.call('build-manifest', source)

  FileUtils.mkdir_p("#{root}/server/DEBIAN")
  template_name = "openvox-server_#{source['sources']['openvox-server']['package_version']}_all.deb"
  File.write("#{root}/server/payload", 'shared server payload')
  File.write("#{root}/server/DEBIAN/control", <<~CONTROL)
    Package: openvox-server
    Version: #{source['sources']['openvox-server']['package_version']}
    Architecture: all
    Maintainer: Selfcheck <nobody@example.invalid>
    Description: Disposable release assembly test
    Depends: openvox-agent (= #{source['sources']['openvox']['package_version']})
  CONTROL
  _, error, status = Open3.capture3('dpkg-deb', '--build', "#{root}/server", "#{root}/dist/#{template_name}")
  raise error unless status.success?
  shared = {
    'checks' => %w[source_tests vault_source_tests server_recipe server_package_tests].to_h { |check| [check, 'passed'] },
    'java' => 'openjdk 25 fixture',
    'server' => template_name,
    'server_sha256' => Digest::SHA256.file("#{root}/dist/#{template_name}").hexdigest
  }
  write.call('source-checks', shared)
  FileUtils.cp_r("#{root}/dist", "#{root}/original")
  reset = lambda do
    FileUtils.rm_rf("#{root}/dist")
    FileUtils.cp_r("#{root}/original", "#{root}/dist")
  end
  _, error, status = run.call('assemble-release')
  raise error unless status.success?
  assembled = read.call('build-manifest')
  raise 'Missing coordinated targets' unless assembled.fetch('targets').keys == targets
  raise 'Legacy source fields changed' unless assembled.fetch('sources') == source.fetch('sources')
  raise 'Legacy checks missing' unless assembled.fetch('checks') == shared.fetch('checks').merge('agent_package_tests' => 'passed')
  targets.each do |target|
    tested = assembled.fetch('targets').fetch(target)
    raise 'Lost shared Java evidence' unless tested.fetch('runtime_inputs').fetch('java') == shared.fetch('java')
    raise 'Wrong target checks' unless tested.fetch('checks') == assembled.fetch('checks')
    package = "openvox-server_#{tested['sources']['openvox-server']['package_version']}_all.deb"
    raise 'Lost server checksum' unless tested.fetch('sha256').fetch(package) == Digest::SHA256.file("#{root}/dist/#{package}").hexdigest
    depends, error, status = Open3.capture3('dpkg-deb', '-f', "#{root}/dist/#{package}", 'Depends')
    raise error unless status.success?
    raise 'Server dependency crossed targets' unless depends.strip == "openvox-agent (= #{tested['sources']['openvox']['package_version']})"
  end

  {
    'build identity' => ->(manifest) { manifest['build'] = '43001' },
    'target identity' => ->(manifest) { manifest['target'] = 'ubuntu26.04' },
    'source snapshot' => ->(manifest) { manifest['sources']['vault']['sha'] = 'b' * 40 },
    'package version' => ->(manifest) { manifest['sources']['openvox']['package_version'].sub!('42001', '43001') },
    'failed agent checks' => ->(manifest) { manifest['checks']['agent_package_tests'] = 'failed' },
    'missing agent checksum' => ->(manifest) { manifest['sha256'] = {} },
    'agent checksum' => ->(manifest) { manifest['sha256'].transform_values! { '0' * 64 } }
  }.each do |name, mutate|
    reset.call
    tested = read.call('build-manifest-ubuntu24.04')
    mutate.call(tested)
    write.call('build-manifest-ubuntu24.04', tested)
    _, _, status = run.call('assemble-release')
    raise "Accepted mismatched #{name}" if status.success?
    raise 'Published a partially assembled manifest' unless read.call('build-manifest') == source
  end
  ['failed checks', 'empty checks', 'missing required check', 'server package identity', 'server checksum'].each do |name|
    reset.call
    invalid_shared = read.call('source-checks')
    case name
    when 'failed checks' then invalid_shared['checks']['source_tests'] = 'failed'
    when 'empty checks' then invalid_shared['checks'] = {}
    when 'missing required check' then invalid_shared['checks'].delete('vault_source_tests')
    when 'server package identity' then invalid_shared['server'] = 'other-server.deb'
    when 'server checksum' then invalid_shared['server_sha256'] = '0' * 64
    end
    write.call('source-checks', invalid_shared)
    _, _, status = run.call('assemble-release')
    raise "Accepted #{name}" if status.success?
  end
end
puts 'Target selection and coordinated release manifest checks passed'
