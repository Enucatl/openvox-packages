require 'yaml'

jobs = YAML.load_file(File.expand_path('../.github/workflows/packages.yml', __dir__)).fetch('jobs')
%w[publish acceptance promote prepare_image server_image].each do |name|
  job = jobs.fetch(name)
  condition = job.fetch('if', '')
  # GitHub otherwise skips descendants of cached source jobs, even after qualification succeeds.
  raise "#{name} inherits the implicit success gate" unless condition.start_with?('always() && ')
  expected = Array(job.fetch('needs')).map { |dependency| "needs.#{dependency}.result == 'success'" }
  raise "#{name} can run after a prerequisite failed" unless condition.split(' && ').drop(1).sort == expected.sort
end
puts 'Publication gates handle skipped source checks and require successful prerequisites'
