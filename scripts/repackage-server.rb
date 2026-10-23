require 'tmpdir'
require 'open3'
require 'fileutils'

abort 'Usage: repackage-server.rb TEMPLATE OUTPUT SERVER_VERSION AGENT_VERSION' unless ARGV.size == 4
template, output, server, agent = ARGV
pattern = /\A[0-9][0-9A-Za-z.+:~]*\+homelab\.([0-9]+)-1\+(ubuntu26\.04|debian13)\z/
server_match, agent_match = [server, agent].map { |version| pattern.match(version) }
abort 'Expected coordinated package versions' unless server_match && agent_match && server_match.captures == agent_match.captures

Dir.mktmpdir do |root|
  archive_members, status = Open3.capture2('ar', 't', template)
  abort 'Cannot read server template' unless status.success?
  control_members = archive_members.lines.map(&:strip).grep(/\Acontrol\.tar(?:\.(?:xz|gz|zst))?\z/)
  abort 'Expected one control archive' unless control_members.size == 1
  member = control_members.first
  compression = { 'control.tar' => 'none', 'control.tar.xz' => 'xz', 'control.tar.gz' => 'gzip', 'control.tar.zst' => 'zstd' }.fetch(member)
  metadata = "#{root}/metadata"
  FileUtils.mkdir_p(metadata)
  abort 'Cannot extract server template control' unless system('dpkg-deb', '--control', template, "#{metadata}/DEBIAN")
  path = "#{metadata}/DEBIAN/control"
  control = File.read(path)
  abort 'Expected server package' unless control.match?(/^Package: openvox-server$/) && control.match?(/^Architecture: all$/)
  old = control.match(/^Version: (.+)$/)&.[](1)
  old_match = old && pattern.match(old)
  abort 'Template is from a different build' unless old_match && old_match[1] == server_match[1]
  dependency = /openvox-agent \(= ([^)]+)\)/
  old_agent = control.scan(dependency)
  abort 'Expected one coordinated agent dependency' unless old_agent.size == 1 && pattern.match(old_agent[0][0])&.captures == old_match.captures
  control = control.sub(/^Version: .+$/, "Version: #{server}").sub(dependency, "openvox-agent (= #{agent})")
  File.write(path, control)
  # Only rebuild control metadata; the original payload keeps its bytes and ownership.
  rebuilt = "#{root}/metadata.deb"
  abort 'Cannot build server control' unless system('dpkg-deb', '--build', '--nocheck', '--root-owner-group', "-Z#{compression}", metadata, rebuilt)
  updated_control, status = Open3.capture2('ar', 'p', rebuilt, member)
  abort 'Cannot read rebuilt control archive' unless status.success?
  File.binwrite("#{root}/#{member}", updated_control)
  FileUtils.cp(template, output)
  abort 'Cannot update server control archive' unless system('ar', 'r', File.expand_path(output), member, chdir: root)
end
