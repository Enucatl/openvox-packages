require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'

sources = File.expand_path(ARGV.fetch(0, File.expand_path('../sources', __dir__)))
configure = File.expand_path('../scripts/configure-build.rb', __dir__)
ssl_version = File.read("#{sources}/jvm-ssl-utils/project.clj").match(/\(defproject org.openvoxproject\/ssl-utils "([^"]+)"/)[1].delete_suffix('-SNAPSHOT')
server_base = File.read("#{sources}/openvox-server/project.clj").match(/\(defproject org.openvoxproject\/puppetserver "([^"]+)"/)[1].delete_suffix('-SNAPSHOT')
server_version = '9.1.1+homelab.42-1+ubuntu26.04'
agent_version = '9.1.0+homelab.42-1+ubuntu26.04'

Dir.mktmpdir do |root|
  build_script = File.read(File.expand_path('../scripts/build-server.sh', __dir__))
  container_script = build_script[/^docker run.*?^BUILD\n(?:\)"\n)?/m]
  probe = container_script.sub(/(?<=<<'BUILD'\n).*?(?=^BUILD$)/m, "cat >/dev/null\nprintf 'continued'\n")
  docker_stub = 'docker() { while [[ $1 != bash ]]; do shift; done; "$@"; }; build=unused; '
  output, error, status = Open3.capture3('bash', '-c', docker_stub + probe)
  raise "A child consumed the remaining build commands: #{error}" unless status.success? && output == 'continued'

  git_env = { 'GIT_CONFIG_SYSTEM' => "#{root}/gitconfig", 'GIT_CONFIG_GLOBAL' => File::NULL,
              'GIT_TEST_ASSUME_DIFFERENT_OWNER' => '1' }
  trust_command = File.read(File.expand_path('../scripts/build-server.sh', __dir__)).lines.find { |line| line.include?('safe.directory') }
  _, error, status = Open3.capture3(git_env, 'bash', '-c', trust_command)
  raise error unless status.success?
  repo = "#{root}/mounted-repo"
  _, error, status = Open3.capture3('git', 'init', repo)
  raise error unless status.success?
  _, error, status = Open3.capture3(git_env, 'git', '-C', repo, 'ls-files')
  raise "Mounted repository is not trusted without user config: #{error}" unless status.success?

  paths = %w[jvm-ssl-utils/project.clj openvox-server/project.clj openvox-server/resources/ext/ezbake.conf openvox-server/resources/ext/build-scripts/jruby-gem-list.txt openvox-server/resources/ext/build-scripts/install-vendored-gems.sh]
  reset = lambda do
    paths.each do |path|
      FileUtils.mkdir_p(File.dirname("#{root}/#{path}"))
      FileUtils.cp("#{sources}/#{path}", "#{root}/#{path}")
    end
  end
  versions_by_target = %w[ubuntu26.04 ubuntu24.04 debian13].map do |target|
    [server_version.sub('ubuntu26.04', target), agent_version.sub('ubuntu26.04', target)]
  end
  [[], *versions_by_target].each do |versions|
    reset.call
    _, error, status = Open3.capture3(RbConfig.ruby, configure, root, *versions)
    raise error unless status.success?
    suffix = versions.empty? ? 'source' : '42'
    project = File.read("#{root}/openvox-server/project.clj")
    raise 'Wrong SSL artifact' unless File.read("#{root}/jvm-ssl-utils/project.clj").include?("(defproject org.openvoxproject/ssl-utils \"#{ssl_version}-homelab.#{suffix}\"")
    raise 'Wrong SSL dependency' unless project.include?("[org.openvoxproject/ssl-utils \"#{ssl_version}-homelab.#{suffix}\"]")
    raise 'Public OpenSSL dependency retained' if File.read("#{root}/openvox-server/resources/ext/build-scripts/jruby-gem-list.txt").include?('jruby-openssl')
    unless versions.empty?
      raise 'Wrong server Maven version' unless project.include?("(defproject org.openvoxproject/puppetserver \"#{server_base}-homelab.42\"")
      raise 'Wrong EZbake self dependency' unless project.scan("[org.openvoxproject/puppetserver \"#{server_base}-homelab.42\"]").size == 2
      raise 'Wrong agent dependency' unless File.read("#{root}/openvox-server/resources/ext/ezbake.conf").include?("openvox-agent (= #{versions[1]})")
    end
    _, error, status = Open3.capture3(RbConfig.ruby, configure, root, *versions)
    raise 'Accepted an already modified project' if status.success?
    raise error unless error.include?('Expected one public jruby-openssl dependency')
  end

  reset.call
  paths.first(2).each do |path|
    File.write("#{root}/#{path}", File.read("#{root}/#{path}").gsub('-SNAPSHOT', ''))
  end
  _, error, status = Open3.capture3(RbConfig.ruby, configure, root, server_version, agent_version)
  raise "Release source versions failed: #{error}" unless status.success?

  [[server_version, agent_version.sub('.42-', '.43-')],
   [server_version, agent_version.sub('ubuntu26.04', 'debian13')],
   [server_version.sub('ubuntu26.04', 'debian12'), agent_version.sub('ubuntu26.04', 'debian12')],
   ['bad', agent_version], [server_version]].each do |versions|
    reset.call
    before = paths.map { |path| File.read("#{root}/#{path}") }
    _, _, status = Open3.capture3(RbConfig.ruby, configure, root, *versions)
    raise 'Accepted invalid versions' if status.success?
    raise 'Changed files on invalid input' unless paths.map { |path| File.read("#{root}/#{path}") } == before
  end
  ['openvox-server/project.clj', 'openvox-server/resources/ext/ezbake.conf'].each do |path|
    reset.call
    File.write("#{root}/#{path}", '')
    before = paths.map { |file| File.read("#{root}/#{file}") }
    _, _, status = Open3.capture3(RbConfig.ruby, configure, root, server_version, agent_version)
    raise 'Accepted a changed dependency' if status.success?
    raise 'Partially changed an invalid recipe' unless paths.map { |file| File.read("#{root}/#{file}") } == before
  end

  reset.call
  _, error, status = Open3.capture3(RbConfig.ruby, configure, root)
  raise error unless status.success?
  FileUtils.cp_r("#{sources}/openvox-server/resources/ext/build-scripts", root)
  FileUtils.cp("#{root}/openvox-server/resources/ext/build-scripts/install-vendored-gems.sh", "#{root}/build-scripts/")
  FileUtils.cp("#{root}/openvox-server/resources/ext/build-scripts/jruby-gem-list.txt", "#{root}/build-scripts/")
  FileUtils.mkdir_p("#{root}/bin")
  File.write("#{root}/bin/java", <<~'SH')
    #!/bin/bash
    printf '%s\n' "$*" >> "$JAVA_LOG"
    if [[ $* == *jruby-openssl* ]]; then
      exit "${JAVA_OPENSSL_STATUS:-0}"
    elif [[ $* == *openvoxserver-ca* ]]; then
      exit "${JAVA_STATUS:-0}"
    fi
  SH
  FileUtils.chmod(0755, "#{root}/bin/java")
  env = { 'PATH' => "#{root}/bin:#{ENV.fetch('PATH')}", 'JAVA_LOG' => "#{root}/java.log", 'DESTDIR' => root }
  installer = "#{root}/build-scripts/install-vendored-gems.sh"
  [false, true].each do |local|
    File.write("#{root}/build-scripts/openvoxserver-ca.gem", 'local gem fixture') if local
    FileUtils.rm_f(env['JAVA_LOG'])
    _, error, status = Open3.capture3(env, 'bash', installer, chdir: root)
    raise error unless status.success?
    openssl_commands = File.readlines(env['JAVA_LOG']).grep(/jruby-openssl/)
    raise 'Expected only the local OpenSSL installation' unless openssl_commands.size == 1 && openssl_commands.first.include?("install --local --ignore-dependencies --no-document #{root}/build-scripts/jruby-openssl.gem")
    commands = File.readlines(env['JAVA_LOG']).grep(/openvoxserver-ca/)
    raise 'Expected one CA installation' unless commands.size == 1
    if local
      raise 'Local CA gem not installed in isolation' unless commands.first.include?("install --local --ignore-dependencies --no-document #{root}/build-scripts/openvoxserver-ca.gem")
    else
      raise 'Public fallback changed' unless commands.first.include?('openvoxserver-ca:3.3.0')
    end
  end
  _, _, status = Open3.capture3(env.merge('JAVA_STATUS' => '23'), 'bash', installer, chdir: root)
  raise 'Ignored gem installer failure' unless status.exitstatus == 23
  _, _, status = Open3.capture3(env.merge('JAVA_OPENSSL_STATUS' => '24'), 'bash', installer, chdir: root)
  raise 'Ignored OpenSSL installer failure' unless status.exitstatus == 24
end
puts 'Coordinated recipe and local CA installation checks passed'
