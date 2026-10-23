require 'tmpdir'
require 'fileutils'
require 'open3'
require 'yaml'

root = File.expand_path('..', __dir__)
workflow = YAML.load_file("#{root}/.github/workflows/packages.yml")
upload = workflow.fetch('jobs').fetch('acceptance').fetch('steps').find { |step| step['name'] == 'Retain acceptance diagnostics' }
raise 'Diagnostics must upload after failure' unless upload.fetch('if') == 'always()'
upload_paths = upload.fetch('with').fetch('path').lines.map(&:strip)
raise 'Upload paths must name individual files' if upload_paths.any? { |path| path.match?(/[?*]/) || path.end_with?('/') }

Dir.mktmpdir do |dir|
  FileUtils.mkdir_p(["#{dir}/bin", "#{dir}/scripts", "#{dir}/tests/acceptance", "#{dir}/sources/vault/lib", "#{dir}/container/test"])
  FileUtils.cp(Dir["#{root}/scripts/acceptance*.sh"] + ["#{root}/scripts/target.sh"], "#{dir}/scripts")
  FileUtils.cp_r("#{root}/apt", dir)
  FileUtils.cp("#{root}/tests/jruby-openssl.rb", "#{dir}/tests")
  File.write("#{dir}/key.asc", 'PUBLIC KEY')
  File.write("#{dir}/bin/docker", <<~'RUBY')
    #!/usr/bin/env ruby
    require 'fileutils'
    case ARGV.shift
    when 'build'
      File.write(ENV.fetch('FIXTURE_DOCKER_ARGS'), ARGV.join("\n"))
      warn 'APT fixture: candidate repository unavailable'
      exit 42
    when 'cp'
      source, destination = ARGV
      FileUtils.cp(ENV.fetch('FIXTURE_CONTAINER') + source.split(':', 2).last, destination)
    end
  RUBY
  FileUtils.chmod(0o755, "#{dir}/bin/docker")
  env = { 'PATH' => "#{dir}/bin:#{ENV.fetch('PATH')}", 'FIXTURE_CONTAINER' => "#{dir}/container", 'FIXTURE_DOCKER_ARGS' => "#{dir}/docker-args", 'AGENT_VERSION' => 'fixture', 'SERVER_VERSION' => 'fixture' }
  %w[ubuntu26.04 ubuntu24.04 debian13].each do |target|
    output, status = Open3.capture2e(env.merge('TARGET' => target), 'bash', "#{dir}/scripts/acceptance.sh", 'https://fixture.invalid', "#{dir}/key.asc")
    raise "Build failure was hidden: #{output}" unless status.exitstatus == 42 && output.include?('build acceptance image and install packages') && output.include?('candidate repository unavailable')
    args = File.readlines("#{dir}/docker-args", chomp: true)
    raise "Wrong upstream replacement fixture for #{target}" unless args.include?("UPSTREAM_RELEASE=openvox9-release-#{target}.deb") && args.include?("UPSTREAM_AGENT_VERSION=9.1.0-1+#{target}")
    raise "Unpinned acceptance image for #{target}" unless args.any? { |arg| arg.start_with?("BASE_IMAGE=#{target.start_with?('ubuntu') ? 'ubuntu' : 'debian'}:") && arg.include?('@sha256:') }
  end
  evidence = "#{dir}/evidence/acceptance"
  raise 'Build log was lost before a container existed' unless File.read("#{evidence}/build.log").include?('candidate repository unavailable')
  raise 'Host failure status was lost' unless File.read("#{evidence}/host-status.txt").include?('exit_code=42')

  expected = upload_paths.map { |path| path.delete_prefix('evidence/acceptance/') }
  (expected - %w[host-status.txt build.log]).each do |path|
    source = if path.start_with?('package-')
               "var/log/puppetlabs/puppetserver/#{path.delete_prefix('package-')}"
             else
               "test/#{path}"
             end
    FileUtils.mkdir_p(File.dirname("#{dir}/container/#{source}"))
    File.write("#{dir}/container/#{source}", "safe diagnostic: #{path}\n")
  end
  %w[vault-state/root-token vault-state/vault.log vault-state/login-openvox.json vault-state/pki-issue.json RSA/root.key ML-DSA-44-lifecycle/state/ca/ca_key.pem ML-DSA-44-lifecycle/vault-enrolled/vault-login.json].each do |path|
    FileUtils.mkdir_p(File.dirname("#{dir}/container/test/#{path}"))
    File.write("#{dir}/container/test/#{path}", 'CREDENTIAL_SENTINEL')
  end
  output, status = Open3.capture2e(env, 'sh', "#{root}/scripts/acceptance-diagnostics.sh", 'fixture', evidence)
  raise output unless status.success?
  actual = Dir.glob("#{evidence}/**/*").select { |path| File.file?(path) }
  raise 'Collector and upload allowlists differ' unless actual.map { |path| path.delete_prefix("#{evidence}/") }.sort == expected.sort
  raise 'Credentials escaped the container' if actual.any? { |path| File.read(path).include?('CREDENTIAL_SENTINEL') }
end
puts 'Acceptance diagnostics checks passed'
