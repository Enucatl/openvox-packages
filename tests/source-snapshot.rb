require 'json'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'

scripts = File.expand_path('../scripts', __dir__)
repos = %w[openvox jvm-ssl-utils openvox-server openvoxserver-ca vault]
real_git, status = Open3.capture2('sh', '-c', 'command -v git')
raise 'Git is required' unless status.success?
real_git = real_git.strip
Dir.mktmpdir do |root|
  FileUtils.mkdir_p(%w[scripts bin upstream].map { |path| "#{root}/#{path}" })
  %w[prepare.sh checkout-sources.sh].each { |script| FileUtils.cp("#{scripts}/#{script}", "#{root}/scripts/#{script}") }
  git = lambda do |*args|
    output, status = Open3.capture2e({ 'GIT_CONFIG_GLOBAL' => '/dev/null', 'GIT_CONFIG_NOSYSTEM' => '1' }, real_git, *args)
    raise output unless status.success?
    output.strip
  end
  heads = repos.to_h do |repo|
    path = "#{root}/upstream/#{repo}.git"
    git.call('init', '--initial-branch=feature/mldsa44', path)
    git.call('-C', path, 'config', 'user.name', 'Snapshot selfcheck')
    git.call('-C', path, 'config', 'user.email', 'selfcheck@example.invalid')
    File.write("#{path}/payload", 'base')
    git.call('-C', path, 'add', 'payload')
    git.call('-C', path, 'commit', '-m', 'Base release')
    git.call('-C', path, 'tag', repo == 'openvox' ? '9.1.0' : '9.1.1') if %w[openvox openvox-server].include?(repo)
    File.write("#{path}/payload", 'resolved fork')
    git.call('-C', path, 'commit', '-am', 'Fork commit')
    [repo, git.call('-C', path, 'rev-parse', 'HEAD')]
  end
  File.write("#{root}/heads.json", JSON.generate(heads))
  File.write("#{root}/bin/gh", <<~RUBY)
    #!#{RbConfig.ruby}
    require 'json'
    File.open('gh-calls.jsonl', 'a') { |file| file.puts JSON.generate(ARGV) }
    repo = ARGV.fetch(1).match(%r{\\Arepos/Enucatl/([^/]+)/commits/feature%2Fmldsa44\\z})&.[](1)
    abort 'Unexpected source lookup' unless repo && ARGV == ['api', "repos/Enucatl/\#{repo}/commits/feature%2Fmldsa44", '--jq', '.sha']
    puts ENV['INVALID_SHA'] == repo ? 'not-a-commit' : JSON.parse(File.read('heads.json')).fetch(repo)
  RUBY
  File.write("#{root}/bin/git", <<~RUBY)
    #!#{RbConfig.ruby}
    require 'json'
    File.open(ENV.fetch('GIT_CALL_LOG'), 'a') { |file| file.puts JSON.generate(ARGV) }
    exec #{real_git.inspect}, *ARGV
  RUBY
  FileUtils.chmod(0755, Dir["#{root}/bin/*"])
  config = "#{root}/gitconfig"
  %w[Enucatl OpenVoxProject].each do |owner|
    git.call('config', '--file', config, '--add', "url.file://#{root}/upstream/.insteadOf", "https://github.com/#{owner}/")
  end
  env = {
    'PATH' => "#{root}/bin:#{ENV.fetch('PATH')}", 'GIT_CONFIG_GLOBAL' => config, 'GIT_CONFIG_NOSYSTEM' => '1',
    'GIT_ALLOW_PROTOCOL' => 'file', 'GIT_CALL_LOG' => "#{root}/git-calls.jsonl",
    'GITHUB_RUN_NUMBER' => '42', 'GITHUB_RUN_ATTEMPT' => '2', 'GITHUB_RUN_ID' => '100',
    'GITHUB_ENV' => "#{root}/github-env"
  }
  output, status = Open3.capture2e(env, 'bash', 'scripts/prepare.sh', chdir: root)
  raise output unless status.success?
  manifest = JSON.parse(File.read("#{root}/dist/build-manifest.json"))
  raise 'Wrong coordinated build identity' unless manifest.values_at('build', 'run', 'attempt') == %w[42002 100 2]
  raise 'Resolved source snapshot changed' unless manifest.fetch('sources').transform_values { |source| source.fetch('sha') } == heads
  { 'openvox' => '9.1.0', 'openvox-server' => '9.1.1' }.each do |repo, base|
    source = manifest.fetch('sources').fetch(repo)
    raise 'Wrong source version' unless source.values_at('base', 'commits_since_tag', 'package_version') == [base, 1, "#{base}+homelab.42002-1+ubuntu26.04"]
    raise 'Version discovery checked out source files' unless git.call('-C', "#{root}/sources/#{repo}", 'rev-parse', '--is-bare-repository') == 'true'
  end
  raise 'Missing build environment' unless File.read(env.fetch('GITHUB_ENV')).include?("BUILD_NUMBER=42002\n")
  gh_calls = File.readlines("#{root}/gh-calls.jsonl")
  raise 'Source heads were not resolved once' unless gh_calls.size == repos.size
  calls = File.readlines(env.fetch('GIT_CALL_LOG')).map { |line| JSON.parse(line) }
  clones = calls.select { |call| call.first == 'clone' }
  raise 'Version discovery cloned unnecessary sources' unless clones.size == 2 && clones.all? { |call| call.include?('--bare') && call.include?('--filter=blob:none') }
  raise 'Version discovery initialized submodules' if calls.any? { |call| call.include?('submodule') }

  moved_heads = repos.to_h do |repo|
    path = "#{root}/upstream/#{repo}.git"
    File.write("#{path}/payload", 'branch moved after resolution')
    git.call('-C', path, 'commit', '-am', 'Next fork commit')
    [repo, git.call('-C', path, 'rev-parse', 'HEAD')]
  end
  File.write("#{root}/heads.json", JSON.generate(moved_heads))
  FileUtils.rm_rf("#{root}/sources")
  output, status = Open3.capture2e(env, 'bash', 'scripts/checkout-sources.sh', *repos, chdir: root)
  raise output unless status.success?
  repos.each do |repo|
    path = "#{root}/sources/#{repo}"
    raise 'Checkout followed the moving branch' unless git.call('-C', path, 'rev-parse', 'HEAD') == heads.fetch(repo) && File.read("#{path}/payload") == 'resolved fork'
  end
  raise 'Checkout resolved source heads again' unless File.readlines("#{root}/gh-calls.jsonl") == gh_calls

  FileUtils.rm_rf("#{root}/sources")
  File.write("#{root}/dist/source-heads.tsv", "openvox\tnot-a-commit\n")
  calls_before = File.read(env.fetch('GIT_CALL_LOG'))
  _, status = Open3.capture2e(env, 'bash', 'scripts/checkout-sources.sh', 'openvox', chdir: root)
  raise 'Checkout accepted an invalid SHA' if status.success?
  raise 'Checkout cloned before validating SHA' unless File.read(env.fetch('GIT_CALL_LOG')) == calls_before
  FileUtils.rm_rf("#{root}/dist")
  _, status = Open3.capture2e(env.merge('INVALID_SHA' => 'jvm-ssl-utils'), 'bash', 'scripts/prepare.sh', chdir: root)
  raise 'Preparation accepted an invalid source SHA' if status.success?
  raise 'Preparation published invalid source manifest' if File.exist?("#{root}/dist/build-manifest.json")
end
puts 'Single source resolution, bare version discovery, and fixed-SHA checkout checks passed'
