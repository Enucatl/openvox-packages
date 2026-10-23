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
  config = "#{root}/gitconfig"
  git_env = { 'GIT_CONFIG_GLOBAL' => config, 'GIT_CONFIG_NOSYSTEM' => '1', 'GIT_ALLOW_PROTOCOL' => 'file' }
  git = lambda do |*args|
    output, status = Open3.capture2e(git_env, real_git, *args)
    raise output unless status.success?
    output.strip
  end
  %w[Enucatl OpenVoxProject].each do |owner|
    git.call('config', '--file', config, '--add', "url.file://#{root}/upstream/.insteadOf", "https://github.com/#{owner}/")
  end
  init = lambda do |path|
    git.call('init', '--initial-branch=feature/mldsa44', path)
    git.call('-C', path, 'config', 'user.name', 'Snapshot selfcheck')
    git.call('-C', path, 'config', 'user.email', 'selfcheck@example.invalid')
  end
  nested = "#{root}/upstream/support.git"
  init.call(nested)
  File.write("#{nested}/payload", 'nested source')
  git.call('-C', nested, 'add', 'payload')
  git.call('-C', nested, 'commit', '-m', 'Nested source')
  nested_sha = git.call('-C', nested, 'rev-parse', 'HEAD')
  heads = repos.to_h do |repo|
    path = "#{root}/upstream/#{repo}.git"
    init.call(path)
    File.write("#{path}/payload", 'base')
    git.call('-C', path, 'add', 'payload')
    git.call('-C', path, 'commit', '-m', 'Base release')
    git.call('-C', path, 'tag', repo == 'openvox' ? '9.1.0' : '9.1.1') if %w[openvox openvox-server].include?(repo)
    if repo == 'openvox'
      File.write("#{path}/.gitmodules", "[submodule \"support\"]\n\tpath = vendor/support\n\turl = https://github.com/Enucatl/support.git\n")
      git.call('-C', path, 'add', '.gitmodules')
      git.call('-C', path, 'update-index', '--add', '--cacheinfo', "160000,#{nested_sha},vendor/support")
    end
    File.write("#{path}/payload", 'pinned fork')
    git.call('-C', path, 'add', 'payload')
    git.call('-C', path, 'commit', '-m', 'Fork commit')
    [repo, git.call('-C', path, 'rev-parse', 'HEAD')]
  end
  init.call(root)
  File.write("#{root}/.gitmodules", repos.map { |repo| "[submodule \"sources/#{repo}\"]\n\tpath = sources/#{repo}\n\turl = https://github.com/Enucatl/#{repo}.git\n" }.join)
  git.call('-C', root, 'add', '.gitmodules', 'scripts')
  heads.each { |repo, sha| git.call('-C', root, 'update-index', '--add', '--cacheinfo', "160000,#{sha},sources/#{repo}") }
  git.call('-C', root, 'commit', '-m', 'Pin source repositories')
  File.write("#{root}/bin/git", <<~RUBY)
    #!#{RbConfig.ruby}
    require 'json'
    File.open(ENV.fetch('GIT_CALL_LOG'), 'a') { |file| file.puts JSON.generate(ARGV) }
    exec #{real_git.inspect}, *ARGV
  RUBY
  FileUtils.chmod(0755, "#{root}/bin/git")
  env = git_env.merge(
    'PATH' => "#{root}/bin:#{ENV.fetch('PATH')}", 'GIT_CALL_LOG' => "#{root}/git-calls.jsonl",
    'GITHUB_RUN_NUMBER' => '42', 'GITHUB_RUN_ATTEMPT' => '2', 'GITHUB_RUN_ID' => '100',
    'GITHUB_ENV' => "#{root}/github-env"
  )
  run = lambda do |script, *args|
    output, status = Open3.capture2e(env, 'bash', "scripts/#{script}.sh", *args, chdir: root)
    raise output unless status.success?
  end
  run.call('prepare')
  manifest_path = "#{root}/dist/build-manifest.json"
  heads_path = "#{root}/dist/source-heads.tsv"
  manifest = JSON.parse(File.read(manifest_path))
  raise 'Wrong coordinated build identity' unless manifest.values_at('build', 'run', 'attempt') == %w[42002 100 2]
  raise 'Source snapshot differs from committed pins' unless manifest.fetch('sources').transform_values { |source| source.fetch('sha') } == heads
  { 'openvox' => '9.1.0', 'openvox-server' => '9.1.1' }.each do |repo, base|
    source = manifest.fetch('sources').fetch(repo)
    raise 'Wrong source version' unless source.values_at('base', 'commits_since_tag', 'package_version') == [base, 1, "#{base}+homelab.42002-1+ubuntu26.04"]
    raise 'Version discovery did not initialize a source checkout' unless git.call('-C', "#{root}/sources/#{repo}", 'rev-parse', '--is-bare-repository') == 'false'
  end
  raise 'Missing build environment' unless File.read(env.fetch('GITHUB_ENV')).include?("BUILD_NUMBER=42002\n")

  moved_heads = repos.to_h do |repo|
    path = "#{root}/upstream/#{repo}.git"
    File.write("#{path}/payload", 'branch moved after pinning')
    git.call('-C', path, 'add', 'payload')
    git.call('-C', path, 'commit', '-m', 'Next fork commit')
    [repo, git.call('-C', path, 'rev-parse', 'HEAD')]
  end
  run.call('checkout-sources', *repos)
  repos.each do |repo|
    path = "#{root}/sources/#{repo}"
    raise 'Checkout followed the moving branch' unless git.call('-C', path, 'rev-parse', 'HEAD') == heads.fetch(repo) && File.read("#{path}/payload") == 'pinned fork'
  end
  raise 'Nested submodule was not initialized' unless git.call('-C', "#{root}/sources/openvox/vendor/support", 'rev-parse', 'HEAD') == nested_sha && File.read("#{root}/sources/openvox/vendor/support/payload") == 'nested source'
  run.call('prepare')
  run.call('checkout-sources', *repos)
  raise 'Rerun changed pinned sources' unless JSON.parse(File.read(manifest_path)) == manifest
  raise 'Rerun appended duplicate source pins' unless File.readlines(heads_path).size == repos.size

  saved_heads = File.read(heads_path)
  File.write(heads_path, saved_heads.sub(heads.fetch('openvox'), 'not-a-commit'))
  calls_before = File.read(env.fetch('GIT_CALL_LOG'))
  _, status = Open3.capture2e(env, 'bash', 'scripts/checkout-sources.sh', 'openvox', chdir: root)
  raise 'Checkout accepted an invalid SHA' if status.success?
  raise 'Checkout mutated Git state before validating SHA' unless File.read(env.fetch('GIT_CALL_LOG')) == calls_before
  File.write(heads_path, saved_heads.sub(heads.fetch('openvox'), moved_heads.fetch('openvox')))
  _, status = Open3.capture2e(env, 'bash', 'scripts/checkout-sources.sh', 'openvox', chdir: root)
  raise 'Checkout accepted a manifest that disagrees with the committed pin' if status.success?

  File.write(heads_path, saved_heads)
  git.call('-C', root, 'update-index', '--cacheinfo', "160000,#{moved_heads.fetch('openvox')},sources/openvox")
  _, status = Open3.capture2e(env, 'bash', 'scripts/checkout-sources.sh', 'openvox', chdir: root)
  raise 'Checkout accepted a staged pin that disagrees with HEAD' if status.success?
  raise 'Checkout advanced to an uncommitted pin' unless git.call('-C', "#{root}/sources/openvox", 'rev-parse', 'HEAD') == heads.fetch('openvox')
  git.call('-C', root, 'commit', '-m', 'Advance OpenVox pin')
  run.call('prepare')
  run.call('checkout-sources', *repos)
  expected_heads = heads.merge('openvox' => moved_heads.fetch('openvox'))
  updated = JSON.parse(File.read(manifest_path)).fetch('sources')
  raise 'Preparation ignored the updated parent pin' unless updated.transform_values { |source| source.fetch('sha') } == expected_heads
  raise 'Version did not follow the updated pin' unless updated.fetch('openvox').fetch('commits_since_tag') == 2
  raise 'Initialized checkout did not advance to the new pin' unless git.call('-C', "#{root}/sources/openvox", 'rev-parse', 'HEAD') == moved_heads.fetch('openvox')
  raise 'Pin update appended duplicate source pins' unless File.readlines(heads_path).size == repos.size
end
puts 'Committed source pins, recursive checkout, reruns, and manifest validation checks passed'
