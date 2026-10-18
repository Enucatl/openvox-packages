require 'json'
require 'tmpdir'
require 'fileutils'
require 'open3'

Dir.mktmpdir do |root|
  FileUtils.mkdir_p(%w[scripts tests docker/server bin].map { |path| "#{root}/#{path}" })
  FileUtils.cp(File.expand_path('../scripts/server-image.sh', __dir__), "#{root}/scripts/")
  File.write("#{root}/docker/server/Dockerfile", "FROM fixture\n")
  File.write("#{root}/openvox-archive-keyring.asc", 'fixture-public-key')
  File.write("#{root}/tests/server-image.sh", "#!/bin/sh\nexit 0\n")
  FileUtils.chmod(0755, "#{root}/tests/server-image.sh")
  manifest = {
    build: '13001',
    sources: {
      openvox: { package_version: '9.1.0+homelab.13001-1+ubuntu26.04', sha: 'agent-source' },
      'openvox-server': { base: '9.1.0', package_version: '9.1.0+homelab.13001-1+ubuntu26.04', sha: 'server-source' }
    }
  }
  File.write("#{root}/manifest.json", JSON.generate(manifest))
  File.write("#{root}/bin/gh", <<~'RUBY')
    #!/usr/bin/env ruby
    require 'json'
    require 'fileutils'
    case ARGV.first(2)
    when ['release', 'view']
      abort 'latest is not a literal release tag' if ARGV[2] == 'latest'
      if ARGV.include?('--jq')
        puts ENV.fetch('LATEST_RELEASE', 'resolute-13001')
      else
        puts File.read(ENV.fetch('RELEASE_FIXTURE'))
      end
    when ['release', 'download']
      FileUtils.cp(ENV.fetch('MANIFEST_FIXTURE'), File.join(ARGV[ARGV.index('--dir') + 1], 'build-manifest.json'))
    when ['release', 'upload']
      FileUtils.cp(ARGV[3], ENV.fetch('UPLOAD_FIXTURE'))
    else
      abort "Unexpected gh command: #{ARGV.inspect}"
    end
  RUBY
  File.write("#{root}/bin/docker", <<~'RUBY')
    #!/usr/bin/env ruby
    require 'json'
    File.open(ENV.fetch('DOCKER_CALLS'), 'a') { |file| file.puts JSON.generate(ARGV) }
    puts "ghcr.io/enucatl/openvox-server@sha256:#{'a' * 64}" if ARGV.first(2) == ['image', 'inspect']
  RUBY
  FileUtils.chmod(0755, Dir["#{root}/bin/*"])
  release = { tagName: 'resolute-13001', body: "Package checks\nAcceptance: passed\n", isDraft: false, isPrerelease: false }
  env = {
    'PATH' => "#{root}/bin:#{ENV.fetch('PATH')}", 'GH_REPO' => 'Enucatl/openvox-packages',
    'GITHUB_SHA' => 'image-source', 'GITHUB_STEP_SUMMARY' => "#{root}/summary",
    'RELEASE_FIXTURE' => "#{root}/release.json", 'MANIFEST_FIXTURE' => "#{root}/manifest.json",
    'UPLOAD_FIXTURE' => "#{root}/uploaded.json", 'DOCKER_CALLS' => "#{root}/docker.jsonl"
  }
  [release.merge(body: 'Acceptance: pending'), release.merge(isDraft: true),
   release.merge(isPrerelease: true), release.merge(tagName: 'noble-13001')].each do |rejected|
    File.write(env.fetch('RELEASE_FIXTURE'), JSON.generate(rejected))
    output, status = Open3.capture2e(env, 'bash', "#{root}/scripts/server-image.sh", 'latest', '--push')
    raise "Accepted unsuitable package release: #{rejected}\n#{output}" if status.success?
    raise 'Built an unsuitable release' if File.exist?(env.fetch('DOCKER_CALLS'))
  end
  File.write(env.fetch('RELEASE_FIXTURE'), JSON.generate(release))
  [manifest.merge(build: '14001'), manifest.merge(build: 'not-a-build')].each do |invalid|
    File.write(env.fetch('MANIFEST_FIXTURE'), JSON.generate(invalid))
    _, status = Open3.capture2e(env, 'bash', "#{root}/scripts/server-image.sh", 'latest', '--push')
    raise 'Accepted inconsistent image provenance' if status.success?
    raise 'Built inconsistent image provenance' if File.exist?(env.fetch('DOCKER_CALLS'))
  end
  File.write(env.fetch('MANIFEST_FIXTURE'), JSON.generate(manifest))
  output, status = Open3.capture2e(env, 'bash', "#{root}/scripts/server-image.sh", 'latest', '--push')
  raise output unless status.success?
  calls = File.readlines(env.fetch('DOCKER_CALLS')).map { |line| JSON.parse(line) }
  build = calls.find { |call| call.first == 'build' }
  raise 'Image did not use the resolved versioned archive' unless build.include?('APT_URL=https://github.com/Enucatl/openvox-packages/releases/download/resolute-13001/')
  manifest.fetch(:sources).each do |component, source|
    key = component == :openvox ? 'AGENT_VERSION' : 'SERVER_VERSION'
    raise "Missing exact #{component} version" unless build.include?("#{key}=#{source.fetch(:package_version)}")
  end
  uploaded = JSON.parse(File.read(env.fetch('UPLOAD_FIXTURE')))
  raise 'Lost package provenance' unless uploaded.fetch('packages') == JSON.parse(JSON.generate(manifest))
  raise 'Missing image source revision' unless uploaded.fetch('image_revision') == 'image-source'
  raise 'Missing registry digest' unless uploaded.fetch('image') == "ghcr.io/enucatl/openvox-server@sha256:#{'a' * 64}"
  expected_tags = %w[9.1.0-mldsa.13001 9.1.0 latest].map { |tag| "ghcr.io/enucatl/openvox-server:#{tag}" }
  raise 'Incorrect image tag aliases' unless uploaded.fetch('tags') == expected_tags
  raise 'Missing upstream version' unless uploaded.fetch('upstream_version') == '9.1.0'
  raise 'Did not push every image tag' unless calls.select { |call| call.first == 'push' }.map(&:last) == expected_tags
  FileUtils.rm_f(env.fetch('DOCKER_CALLS'))
  output, status = Open3.capture2e(env.merge('LATEST_RELEASE' => 'resolute-14001'), 'bash', "#{root}/scripts/server-image.sh", 'resolute-13001', '--push')
  raise output unless status.success?
  calls = File.readlines(env.fetch('DOCKER_CALLS')).map { |line| JSON.parse(line) }
  raise 'An older release moved an alias backward' unless calls.select { |call| call.first == 'push' }.map(&:last) == [expected_tags.first]
end
puts 'Server image publication checks passed'
