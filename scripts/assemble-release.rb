require 'json'
require 'digest'

manifest = JSON.parse(File.read('dist/build-manifest.json'))
shared = JSON.parse(File.read('dist/source-checks.json'))
manifest['source_verification'] = shared.fetch('source_verification') if shared.key?('source_verification')
abort 'Shared source checks did not pass' unless %w[source_tests vault_source_tests server_recipe server_package_tests].all? { |check| shared.fetch('checks').fetch(check) == 'passed' } && shared.fetch('checks').values.all? { |value| value == 'passed' }
template_version = manifest.fetch('sources').fetch('openvox-server').fetch('package_version')
template = "openvox-server_#{template_version}_all.deb"
abort 'Mismatched shared server package' unless shared.fetch('server') == template
abort 'Shared server package changed' unless Digest::SHA256.file("dist/#{template}").hexdigest == shared.fetch('server_sha256')
manifest['targets'] = %w[ubuntu26.04 debian13].to_h do |target|
  tested = JSON.parse(File.read("dist/build-manifest-#{target}.json"))
  abort 'Mismatched target build identity' unless tested.fetch('target') == target && %w[build run attempt].all? { |key| tested.fetch(key) == manifest.fetch(key) }
  abort 'Mismatched source snapshot' unless manifest.fetch('sources').all? { |repo, source| tested.fetch('sources').fetch(repo).fetch('sha') == source.fetch('sha') }
  %w[openvox openvox-server].each do |repo|
    expected = manifest.fetch('sources').fetch(repo).fetch('package_version').delete_suffix('ubuntu26.04') + target
    abort 'Mismatched target package version' unless tested.fetch('sources').fetch(repo).fetch('package_version') == expected
  end
  abort 'Agent package checks did not pass' unless tested.fetch('checks').fetch('agent_package_tests') == 'passed'
  agent = tested.fetch('sources').fetch('openvox').fetch('package_version')
  abort 'Missing tested agent checksum' unless tested.fetch('sha256').key?("openvox-agent_#{agent}_amd64.deb")
  tested.fetch('sha256').each do |package, checksum|
    abort "Agent package changed: #{package}" unless Digest::SHA256.file("dist/#{package}").hexdigest == checksum
  end
  server = tested.fetch('sources').fetch('openvox-server').fetch('package_version')
  unless target == 'ubuntu26.04'
    abort 'Cannot repackage shared server' unless system('ruby', 'scripts/repackage-server.rb', "dist/openvox-server_#{template_version}_all.deb", "dist/openvox-server_#{server}_all.deb", server, agent)
  end
  tested['checks'].merge!(shared.fetch('checks'))
  tested['runtime_inputs']['java'] = shared.fetch('java')
  tested['sha256']["openvox-server_#{server}_all.deb"] = Digest::SHA256.file("dist/openvox-server_#{server}_all.deb").hexdigest
  [target, tested]
end
# Preserve the original 26.04 manifest fields for existing release consumers.
manifest.merge!(manifest.fetch('targets').fetch('ubuntu26.04').reject { |key, _| key == 'target' })
File.write('dist/build-manifest.json', JSON.pretty_generate(manifest) + "\n")
