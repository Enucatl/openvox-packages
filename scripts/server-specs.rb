require 'rake'

# The rake task configures embedded JRuby and its own Bundler independently of MRI.
Bundler.with_unbundled_env { Rake.application.run(['spec']) }
