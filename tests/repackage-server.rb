require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'rubygems/package'
require 'stringio'

script = File.expand_path('../scripts/repackage-server.rb', __dir__)
server = '9.1.1+homelab.42-1+ubuntu26.04'
agent = '9.1.0+homelab.42-1+ubuntu26.04'
control = <<~CONTROL
  Package: openvox-server
  Version: #{server}
  Architecture: all
  Maintainer: Fixture <fixture@example.org>
  Depends: openjdk-25-jre-headless, openvox-agent (= #{agent})
  Description: Server fixture
CONTROL

def tar(entries)
  entries.map do |name, body, mode, uid, gid, type, link|
    Gem::Package::TarHeader.new(name: name, mode: mode, uid: uid, gid: gid, size: body.bytesize,
                              mtime: 1_700_000_000, typeflag: type || '0', linkname: link || '',
                              prefix: '', uname: '', gname: '').to_s + body + "\0" * ((-body.bytesize) % 512)
  end.join + "\0" * 1024
end

def members(archive)
  Gem::Package::TarReader.new(StringIO.new(archive)).to_h do |entry|
    [entry.full_name, [entry.header.mode, entry.header.uid, entry.header.gid, entry.header.typeflag,
                       entry.header.linkname, entry.read]]
  end
end

def capture(*command)
  output, error, status = Open3.capture3(*command, binmode: true)
  raise "#{command.join(' ')}: #{error}" unless status.success?
  output
end

Dir.mktmpdir do |root|
  payload = tar([
    ['./opt/puppetlabs/server/server.jar', "jar fixture\0\xff".b, 0644, 0, 0],
    ['./var/lib/puppet/server-state', 'owned by service account', 0640, 4242, 4343],
    ['./etc/puppetlabs/puppetserver/fixture.conf', 'configuration', 0644, 0, 0],
    ['./opt/puppetlabs/server/current', '', 0777, 0, 0, '2', 'server.jar']
  ])
  scripts = [['./postinst', "#!/bin/sh\nexit 0\n", 0755, 0, 0],
             ['./conffiles', "/etc/puppetlabs/puppetserver/fixture.conf\n", 0644, 0, 0]]
  build_template = lambda do |text, compression = 'none'|
    File.binwrite("#{root}/debian-binary", "2.0\n")
    suffix = { 'none' => '', 'xz' => '.xz', 'gzip' => '.gz' }.fetch(compression)
    control_member, data_member = ["#{root}/control.tar#{suffix}", "#{root}/data.tar#{suffix}"]
    [ [control_member, tar([['./control', text, 0644, 0, 0], *scripts])], [data_member, payload] ].each do |path, content|
      unless compression == 'none'
        content, error, status = Open3.capture3(compression, '-c', stdin_data: content, binmode: true)
        raise error unless status.success?
      end
      File.binwrite(path, content)
    end
    path = "#{root}/template.deb"
    FileUtils.rm_f(path)
    capture('ar', 'qc', path, "#{root}/debian-binary", control_member, data_member)
    path
  end
  %w[none xz gzip].each do |compression|
    template = build_template.call(control, compression)
    original_control = members(capture('dpkg-deb', '--ctrl-tarfile', template))
    data_member = capture('ar', 't', template).lines.map(&:strip).find { |name| name.start_with?('data.tar') }
    %w[debian13].each do |target|
      target_server, target_agent = [server, agent].map { |version| version.sub('ubuntu26.04', target) }
      output = "#{root}/#{target}-#{compression}.deb"
      capture(RbConfig.ruby, script, template, output, target_server, target_agent)
      raise 'Wrong server version' unless capture('dpkg-deb', '-f', output, 'Version').strip == target_server
      raise 'Wrong agent dependency' unless capture('dpkg-deb', '-f', output, 'Depends').include?("openvox-agent (= #{target_agent})")
      raise 'Server payload or ownership changed' unless capture('dpkg-deb', '--fsys-tarfile', output) == payload
      raise 'Compressed payload member changed' unless capture('ar', 'p', output, data_member) == capture('ar', 'p', template, data_member)
      raise 'Archive member order changed' unless capture('ar', 't', output) == capture('ar', 't', template)
      repacked_control = members(capture('dpkg-deb', '--ctrl-tarfile', output))
      scripts.each do |name, *|
        raise "Maintainer file changed: #{name}" unless repacked_control.fetch(name) == original_control.fetch(name)
      end
    end
  end

  cases = [
    [control, server.sub('.42-', '.43-'), agent.sub('.42-', '.43-')],
    [control, server.sub('ubuntu26.04', 'ubuntu24.04'), agent.sub('ubuntu26.04', 'debian13')],
    [control.sub('Package: openvox-server', 'Package: other'), server, agent],
    [control.sub('Architecture: all', 'Architecture: amd64'), server, agent],
    [control.sub(agent, agent.sub('.42-', '.43-')), server, agent],
    [control.sub(agent, agent.sub('ubuntu26.04', 'debian13')), server, agent]
  ]
  cases.each do |text, target_server, target_agent|
    template = build_template.call(text)
    output = "#{root}/invalid.deb"
    _, _, status = Open3.capture3(RbConfig.ruby, script, template, output, target_server, target_agent)
    raise 'Accepted an invalid server template or version pair' if status.success?
    raise 'Wrote output for invalid input' if File.exist?(output)
  end
  template = "#{root}/broken.deb"
  File.write(template, 'not a Debian archive')
  _, _, status = Open3.capture3(RbConfig.ruby, script, template, "#{root}/invalid.deb", server, agent)
  raise 'Accepted a broken archive' if status.success?
  raise 'Wrote output for a broken archive' if File.exist?("#{root}/invalid.deb")
end
puts 'Server repackaging checks passed'
