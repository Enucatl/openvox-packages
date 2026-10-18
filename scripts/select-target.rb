require 'json'

target = ENV.fetch('TARGET', 'ubuntu26.04')
abort 'Unsupported package target' unless %w[ubuntu26.04 ubuntu24.04 debian13].include?(target)
manifest = JSON.parse(File.read('dist/build-manifest.json'))
manifest['target'] = target
%w[openvox openvox-server].each do |repo|
  version = manifest.fetch('sources').fetch(repo).fetch('package_version')
  abort 'Expected Ubuntu 26.04 source snapshot' unless version.end_with?('-1+ubuntu26.04')
  manifest['sources'][repo]['package_version'] = version.delete_suffix('ubuntu26.04') + target
end
File.write("dist/build-manifest-#{target}.json", JSON.pretty_generate(manifest) + "\n")
File.open(ENV.fetch('GITHUB_ENV'), 'a') do |file|
  file.puts "BUILD_NUMBER=#{manifest.fetch('build')}"
  file.puts "AGENT_VERSION=#{manifest['sources']['openvox']['package_version']}"
  file.puts "SERVER_VERSION=#{manifest['sources']['openvox-server']['package_version']}"
end
