require 'tmpdir'
require 'fileutils'

sources = ARGV.fetch(0, File.expand_path('../sources', __dir__))
ssl_version = File.read("#{sources}/jvm-ssl-utils/project.clj").match(/\(defproject org.openvoxproject\/ssl-utils "([^"]+)"/)[1].delete_suffix('-SNAPSHOT')
script = File.read(File.expand_path('../scripts/build-server.sh', __dir__))
rewrite = script.split("<<'RUBY'\n", 2).fetch(1).split("\nRUBY", 2).first
Dir.mktmpdir do |root|
  FileUtils.mkdir_p("#{root}/openvox-server/resources/ext")
  FileUtils.mkdir_p("#{root}/jvm-ssl-utils")
  FileUtils.cp("#{sources}/jvm-ssl-utils/project.clj", "#{root}/jvm-ssl-utils/project.clj")
  FileUtils.cp("#{sources}/openvox-server/Dockerfile", "#{root}/openvox-server/Dockerfile")
  FileUtils.cp("#{sources}/openvox-server/project.clj", "#{root}/openvox-server/project.clj")
  FileUtils.cp("#{sources}/openvox-server/resources/ext/ezbake.conf", "#{root}/openvox-server/resources/ext/ezbake.conf")
  FileUtils.cp_r("#{sources}/openvox-server/resources/ext/build-scripts", "#{root}/openvox-server/resources/ext/")
  ARGV.replace([root, '9.1.1+homelab.42-1+ubuntu26.04', '9.1.0+homelab.42-1+ubuntu26.04'])
  eval(rewrite, binding, 'build-server.sh recipe')
  raise 'Wrong SSL version' unless File.read("#{root}/jvm-ssl-utils/project.clj").include?("#{ssl_version}-homelab.42")
  raise 'Wrong builder Java' unless File.read("#{root}/openvox-server/Dockerfile").include?('java-25-openjdk-headless')
  project = File.read("#{root}/openvox-server/project.clj")
server_base = File.read("#{sources}/openvox-server/project.clj").match(/\(defproject org.openvoxproject\/puppetserver "([^"]+)"/)[1].delete_suffix('-SNAPSHOT')
raise 'Wrong server Maven version' unless project.include?("(defproject org.openvoxproject/puppetserver \"#{server_base}-homelab.42\"")
raise 'Wrong EZbake self dependency' unless project.scan("[org.openvoxproject/puppetserver \"#{server_base}-homelab.42\"]").size == 2
  raise 'Wrong SSL dependency' unless project.include?("[org.openvoxproject/ssl-utils \"#{ssl_version}-homelab.42\"]")
  raise 'Missing security file' unless project.include?(':project-files [{:file "resources/ext/java.security.mldsa"')
  raise 'Wrong agent dependency' unless File.read("#{root}/openvox-server/resources/ext/ezbake.conf").include?('openvox-agent (= 9.1.0+homelab.42-1+ubuntu26.04)')
  raise 'Public CA gem still listed' unless File.empty?("#{root}/openvox-server/resources/ext/build-scripts/mri-gem-list-no-dependencies.txt")
  raise 'Invalid gem installer' unless system('bash', '-n', "#{root}/openvox-server/resources/ext/build-scripts/install-vendored-gems.sh")
  begin
    eval(rewrite, binding, 'build-server.sh recipe')
    raise 'Unexpectedly accepted changed inputs'
  rescue RuntimeError => error
    raise unless error.message == 'Unexpected builder Java version'
  end
end
puts 'Server recipe checks passed'
