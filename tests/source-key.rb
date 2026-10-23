require 'json'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'

script = File.expand_path('../scripts/source-key.rb', __dir__)
Dir.mktmpdir do |root|
  FileUtils.mkdir_p(["#{root}/scripts", "#{root}/dist"])
  FileUtils.cp(script, "#{root}/scripts/source-key.rb")
  recipe = "#{root}/scripts/recipe.sh"
  File.write(recipe, 'original recipe')
  %w[init add].each do |command|
    args = command == 'add' ? ['scripts'] : []
    _, error, status = Open3.capture3('git', '-C', root, command, *args)
    raise error unless status.success?
  end
  manifest = { 'build' => '42001', 'sources' => { 'openvox' => { 'sha' => 'a' * 40, 'package_version' => 'version-one' } } }
  path = "#{root}/dist/build-manifest.json"
  env = { 'ImageOS' => 'ubuntu26', 'ImageVersion' => 'fixture-one' }
  key = lambda do |overrides = {}|
    File.write(path, JSON.generate(manifest))
    output, error, status = Open3.capture3(env.merge(overrides), RbConfig.ruby, 'scripts/source-key.rb', chdir: root)
    raise error unless status.success?
    raise 'Invalid qualification key' unless output.match?(/\A[0-9a-f]{64}\n\z/)
    output
  end
  original = key.call
  manifest['build'] = '43001'
  manifest['sources']['openvox']['package_version'] = 'version-two'
  raise 'Build number invalidates source checks' unless key.call == original
  raise 'Runner change reused source checks' if key.call('ImageVersion' => 'fixture-two') == original
  manifest['sources']['openvox']['sha'] = 'b' * 40
  raise 'Source change reused source checks' if key.call == original
  manifest['sources']['openvox']['sha'] = 'a' * 40
  File.write(recipe, 'changed recipe')
  raise 'Recipe change reused source checks' if key.call == original
  File.write(recipe, 'original recipe')
  File.write("#{root}/scripts/untracked.sh", 'untracked artifact')
  raise 'Untracked artifact invalidates source checks' unless key.call == original
  manifest['sources']['openvox']['sha'] = 'invalid'
  File.write(path, JSON.generate(manifest))
  _, _, status = Open3.capture3(env, RbConfig.ruby, 'scripts/source-key.rb', chdir: root)
  raise 'Invalid source commit accepted' if status.success?
end
puts 'Source qualification key checks passed'
