shard = ARGV.fetch(0)
abort 'Expected all, ca, jruby or other shard' unless %w[all ca jruby other].include?(shard)
namespaces = Dir['test/{unit,integration}/**/*.clj'].sort.map do |path|
  File.read(path, encoding: 'UTF-8').match(/^\(ns\s+([\w.-]+)/)&.[](1) or abort "Missing test namespace: #{path}"
end
abort 'No server test namespaces found' if namespaces.empty?
abort 'Duplicate server test namespace' unless namespaces.uniq == namespaces
namespaces.each do |namespace|
  group = if namespace.start_with?('puppetlabs.puppetserver.certificate-authority', 'puppetlabs.services.ca.', 'puppetlabs.services.certificate-authority.')
            'ca'
          elsif namespace.start_with?('puppetlabs.services.jruby.')
            'jruby'
          else
            'other'
          end
  puts namespace if shard == 'all' || shard == group
end
