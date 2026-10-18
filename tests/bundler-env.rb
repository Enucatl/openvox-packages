require 'tmpdir'
require 'open3'
require 'rbconfig'

script = File.read(File.expand_path('../scripts/source-tests.sh', __dir__))
bundle = [RbConfig.ruby, Gem.bin_path('bundler', 'bundle')]
expression = script.match(/bundle exec ruby -rrake -e '([^']+)'/).captures.first
Dir.mktmpdir do |root|
  rake = Gem::Specification.find_by_name('rake').version
  File.write("#{root}/Gemfile", "source 'https://rubygems.org'\ngem 'rake', '= #{rake}'\n")
  File.write("#{root}/Rakefile", <<~'TASK')
    require 'rbconfig'
    task :spec do
      abort 'MRI Bundler leaked into child' unless system(RbConfig.ruby, '-e', <<~'CHECK')
        abort 'RUBYOPT contains Bundler' if ENV.fetch('RUBYOPT', '').include?('bundler/setup')
        abort 'RUBYLIB contains Bundler' if ENV.fetch('RUBYLIB', '').split(File::PATH_SEPARATOR).any? { |path| path.include?('/bundler-') }
        abort 'BUNDLE_BIN_PATH inherited' if ENV.key?('BUNDLE_BIN_PATH')
        abort 'BUNDLE_GEMFILE inherited' if ENV.key?('BUNDLE_GEMFILE')
        puts 'Rake child environment is clean'
      CHECK
    end
  TASK
  env = { 'BUNDLE_GEMFILE' => "#{root}/Gemfile" }
  out, status = Open3.capture2e(env, *bundle, 'lock', '--local', chdir: root)
  abort out unless status.success?
  _, inherited = Open3.capture2e(env, *bundle, 'exec', 'ruby', '-rrake', '-e', 'Rake.application.run(["spec"])', chdir: root)
  raise 'Regression fixture did not detect the original leak' if inherited.success?
  out, status = Open3.capture2e(env, *bundle, 'exec', 'ruby', '-rrake', '-e', expression, chdir: root)
  abort out unless status.success?
  raise 'Rake child never ran' unless out.include?('Rake child environment is clean')
end
puts 'Bundler environment regression passed'
