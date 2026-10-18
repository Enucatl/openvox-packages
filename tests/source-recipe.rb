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
  ARGV.replace([root])
  eval(rewrite, binding, 'source-tests.sh recipe')
  raise 'Wrong local SSL dependency' unless File.read("#{root}/openvox-server/project.clj").include?("[org.openvoxproject/ssl-utils \"#{ssl_version}-homelab.source\"]")
  raise 'Wrong local SSL artifact' unless File.read("#{root}/jvm-ssl-utils/project.clj").include?("#{ssl_version}-homelab.source")

  vault_script = File.read(File.expand_path('../scripts/test-vault.sh', __dir__))
  gemfile_recipe = vault_script.scan(/<<'RUBY'\n(.*?)\nRUBY/m).last.first
  ARGV.replace(["#{root}/openvox"])
  Dir.chdir("#{root}/vault") do
    File.write('Gemfile', 'original developer bundle')
    eval(gemfile_recipe, binding, 'test-vault.sh recipe')
    gemfile = File.read('Gemfile.packages')
    raise 'Wrong local gem' unless gemfile.include?("gem 'openvox', path: \"#{root}/openvox\"")
    raise 'Wrong helper' unless gemfile.include?("path: '.package-test-gems/puppetlabs_spec_helper-8.0.0'")
    raise 'Legacy facts helper' unless gemfile.include?("gem 'rspec-puppet-facts', '~> 6.3'")
    raise 'Developer bundle changed' unless File.read('Gemfile') == 'original developer bundle'
    raise 'Invalid test Gemfile' unless system('ruby', '-c', 'Gemfile.packages')
  end
end
puts 'Source recipe checks passed'
