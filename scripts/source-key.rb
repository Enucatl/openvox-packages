require 'json'
require 'digest'
require 'open3'

abort 'Usage: source-key.rb [MANIFEST]' if ARGV.size > 1
manifest = JSON.parse(File.read(ARGV.fetch(0, 'dist/build-manifest.json')))
sources = manifest.fetch('sources').sort.to_h.transform_values { |source| source.fetch('sha') }
abort 'Expected source commits' if sources.empty? || sources.values.any? { |sha| !sha.match?(/\A[0-9a-f]{40}\z/) }
root = File.expand_path('..', __dir__)
files, status = Open3.capture2('git', '-C', root, 'ls-files', '-z', '--', 'scripts', 'tests', 'docker/server', '.github/workflows', 'apt/*.pref', 'openvox-archive-keyring.asc')
abort 'Cannot list source-check recipes' unless status.success?
# shortcut: floating dependencies expire this qualification daily; use locked inputs for longer reuse.
identity = { sources: sources, image_os: ENV.fetch('ImageOS', ''), image_version: ENV.fetch('ImageVersion', ''), day: Time.now.utc.strftime('%F') }
digest = Digest::SHA256.new.update(JSON.generate(identity))
files.split("\0").sort.each { |path| digest.update(path).update("\0").update(File.binread("#{root}/#{path}")).update("\0") }
puts digest.hexdigest
