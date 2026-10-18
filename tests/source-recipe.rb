require 'tmpdir'
require 'fileutils'

sources = ARGV.fetch(0, File.expand_path('../sources', __dir__))
ssl_version = File.read("#{sources}/jvm-ssl-utils/project.clj").match(/\(defproject org.openvoxproject\/ssl-utils "([^"]+)"/)[1].delete_suffix('-SNAPSHOT')
script = File.read(File.expand_path('../scripts/source-tests.sh', __dir__))
rewrite = script.split("<<'RUBY'\n", 2).fetch(1).split("\nRUBY", 2).first
Dir.mktmpdir do |root|
  %w[jvm-ssl-utils openvox-server vault openvox].each { |repo| FileUtils.mkdir_p("#{root}/#{repo}") }
  %w[jvm-ssl-utils openvox-server].each do |repo|
    FileUtils.cp("#{sources}/#{repo}/project.clj", "#{root}/#{repo}/project.clj")
  end
  vault = File.exist?("#{sources}/vault/Gemfile") ? 'vault' : 'vault-hiera'
  FileUtils.cp("#{sources}/#{vault}/Gemfile", "#{root}/vault/Gemfile")
  ARGV.replace([root])
  eval(rewrite, binding, 'source-tests.sh recipe')
  raise 'Wrong local SSL dependency' unless File.read("#{root}/openvox-server/project.clj").include?("[org.openvoxproject/ssl-utils \"#{ssl_version}-homelab.source\"]")
  raise 'Wrong local SSL artifact' unless File.read("#{root}/jvm-ssl-utils/project.clj").include?("#{ssl_version}-homelab.source")
  gemfile = File.read("#{root}/vault/Gemfile")
  raise 'Wrong gem name' unless gemfile.include?("gems['openvox'] = location_for(")
  raise 'Wrong local gem path' unless gemfile.include?("file://#{root}/openvox")
  raise 'Invalid Vault Gemfile' unless system('ruby', '-c', "#{root}/vault/Gemfile")
  begin
    eval(rewrite, binding, 'source-tests.sh recipe')
    raise 'Unexpectedly accepted changed inputs'
  rescue RuntimeError => error
    raise unless error.message == 'Vault Puppet dependency changed'
  end
end
puts 'Source recipe checks passed'
