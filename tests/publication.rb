require 'json'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'

root_path = File.expand_path('..', __dir__)
targets = %w[ubuntu26.04 debian13]
snapshot = lambda do |build|
  per_target = targets.to_h do |target|
    [target, { 'sources' => {
      'openvox' => { 'package_version' => "9.1.0+homelab.#{build}-1+#{target}" },
      'openvox-server' => { 'package_version' => "9.1.1+homelab.#{build}-1+#{target}" }
    } }]
  end
  per_target.fetch('ubuntu26.04').merge('build' => build, 'targets' => per_target)
end

Dir.mktmpdir do |root|
  FileUtils.mkdir_p(%w[bin scripts apt fixture/packages].map { |path| "#{root}/#{path}" })
  FileUtils.cp("#{root_path}/scripts/publish.sh", "#{root}/scripts/publish.sh")
  FileUtils.cp(Dir["#{root_path}/apt/*.pref"], "#{root}/apt")
  File.write("#{root}/RELEASE-NOTES.md", 'Coordinated release fixture')
  File.write("#{root}/scripts/archive.sh", <<~'SH')
    #!/usr/bin/env bash
    set -euo pipefail
    touch archive-called
    for metadata in Packages Packages.gz Release InRelease Release.gpg SHA256SUMS; do
      printf 'signed archive fixture\n' > "dist/$metadata"
    done
  SH
  FileUtils.chmod(0755, "#{root}/scripts/archive.sh")
  File.write("#{root}/bin/gh", <<~RUBY)
    #!#{RbConfig.ruby}
    require 'json'
    require 'fileutils'
    File.open('gh-calls.jsonl', 'a') { |file| file.puts JSON.generate(ARGV) }
    case ARGV.first(2)
    when ['api', '--paginate']
      puts JSON.generate([[{ 'draft' => false, 'body' => 'Acceptance: passed' }]])
    when ['api', 'repos/example/packages/releases/latest']
      puts 'resolute-41001'
    when ['api', 'repos/example/packages/releases/tags/resolute-41001']
      puts 'Acceptance: passed'
    when ['release', 'download']
      pattern = ARGV.fetch(ARGV.index('--pattern') + 1)
      abort 'download failed fixture' if ENV['FAIL_DOWNLOAD'] == pattern || ENV['FAIL_DOWNLOAD'] == 'all'
      if pattern == 'build-manifest.json'
        FileUtils.cp('fixture/previous.json', ARGV.fetch(ARGV.index('--output') + 1))
      else
        paths = Dir.glob("fixture/packages/\#{pattern}")
        abort "Missing previous package fixture: \#{pattern}" unless paths.size == 1
        FileUtils.cp(paths, ARGV.fetch(ARGV.index('--dir') + 1))
      end
    when ['release', 'create']
      exit 0
    else
      abort "Unexpected gh call: \#{ARGV.inspect}"
    end
  RUBY
  FileUtils.chmod(0755, "#{root}/bin/gh")
  current = snapshot.call('42001')
  previous = snapshot.call('41001')
  package_name = ->(kind, data) { "openvox-#{kind}_#{data.fetch('sources').fetch(kind == 'agent' ? 'openvox' : 'openvox-server').fetch('package_version')}_#{kind == 'agent' ? 'amd64' : 'all'}.deb" }
  env = {
    'PATH' => "#{root}/bin:#{ENV.fetch('PATH')}", 'GH_REPO' => 'example/packages',
    'BUILD_NUMBER' => '42001', 'GITHUB_SHA' => 'a' * 40,
    'AGENT_VERSION' => current['sources']['openvox']['package_version'],
    'SERVER_VERSION' => current['sources']['openvox-server']['package_version'],
    'GITHUB_ENV' => "#{root}/github-env", 'GITHUB_OUTPUT' => "#{root}/github-output"
  }
  reset = lambda do |old|
    FileUtils.rm_rf("#{root}/dist")
    FileUtils.mkdir_p("#{root}/dist")
    %w[gh-calls.jsonl archive-called github-env github-output].each { |name| FileUtils.rm_f("#{root}/#{name}") }
    File.write("#{root}/dist/build-manifest.json", JSON.generate(current))
    File.write("#{root}/fixture/previous.json", JSON.generate(old))
    current.fetch('targets').each_value do |data|
      %w[agent server].each { |kind| File.write("#{root}/dist/#{package_name.call(kind, data)}", 'current package fixture') }
    end
    previous.fetch('targets').each_value do |data|
      %w[agent server].each { |kind| File.write("#{root}/fixture/packages/#{package_name.call(kind, data)}", 'previous package fixture') }
    end
  end
  [previous.reject { |key, _| key == 'targets' }, previous].each do |old|
    reset.call(old)
    output, status = Open3.capture2e(env, 'bash', 'scripts/publish.sh', chdir: root)
    raise output unless status.success?
    expected_targets = old.key?('targets') ? targets : ['ubuntu26.04']
    result = JSON.parse(File.read("#{root}/dist/build-manifest.json"))
    expected = expected_targets.to_h do |target|
      [target, %w[agent server].to_h do |kind|
        repo = kind == 'agent' ? 'openvox' : 'openvox-server'
        [kind, previous['targets'][target]['sources'][repo]['package_version']]
      end]
    end
    raise 'Wrong retained target versions' unless result.fetch('previous') == expected
    expected_packages = current['targets'].values.flat_map { |data| %w[agent server].map { |kind| package_name.call(kind, data) } }
    expected_packages += expected_targets.flat_map { |target| %w[agent server].map { |kind| package_name.call(kind, previous['targets'][target]) } }
    raise 'Retained the wrong package pairs' unless Dir["#{root}/dist/*.deb"].map { |path| File.basename(path) }.sort == expected_packages.sort
    calls = File.readlines("#{root}/gh-calls.jsonl").map { |line| JSON.parse(line) }
    create = calls.find { |call| call.first(2) == %w[release create] }
    raise 'Did not create candidate' unless create && File.exist?("#{root}/archive-called")
    raise 'Candidate unexpectedly promoted' unless create.include?('--latest=false')
    raise 'Wrong release revision' unless create.fetch(create.index('--target') + 1) == env.fetch('GITHUB_SHA')
    raise 'Wrong candidate tag' unless create[2] == 'resolute-42001'
    targets.each { |target| raise 'Missing published target preferences' unless create.include?("dist/#{target}.pref") }
    expected_url = 'https://github.com/example/packages/releases/download/resolute-42001/'
    raise 'Wrong candidate outputs' unless File.read(env.fetch('GITHUB_OUTPUT')) == "tag=resolute-42001\nurl=#{expected_url}\n"
    raise 'Wrong candidate environment' unless File.read(env.fetch('GITHUB_ENV')) == "CANDIDATE_TAG=resolute-42001\nCANDIDATE_URL=#{expected_url}\n"
  end

  ['same version', 'older version', 'manifest download failure', 'package download failure'].each do |failure|
    old = Marshal.load(Marshal.dump(previous))
    if failure.end_with?('version')
      old['targets']['debian13']['sources']['openvox-server']['package_version'] = current['targets']['debian13']['sources']['openvox-server']['package_version'].sub('42001', failure == 'same version' ? '42001' : '43001')
    end
    reset.call(old)
    overrides = case failure
                when 'manifest download failure' then { 'FAIL_DOWNLOAD' => 'build-manifest.json' }
                when 'package download failure' then { 'FAIL_DOWNLOAD' => 'openvox-agent_9.1.0+homelab.41001-1+ubuntu26.04_*.deb' }
                else {}
                end
    _, status = Open3.capture2e(env.merge(overrides), 'bash', 'scripts/publish.sh', chdir: root)
    raise "Accepted #{failure}" if status.success?
    calls = File.readlines("#{root}/gh-calls.jsonl").map { |line| JSON.parse(line) }
    raise "Archived after #{failure}" if File.exist?("#{root}/archive-called")
    raise "Published after #{failure}" if calls.any? { |call| call.first(2) == %w[release create] }
  end
end
puts 'Publication retention, version guards, and candidate output checks passed'
