require 'pathname'

abort 'Usage: configure-build.rb SOURCES [SERVER_VERSION AGENT_VERSION]' unless [1, 3].include?(ARGV.size)
root, version, agent = ARGV
suffix = 'source'
if version
  pattern = /\A[0-9][0-9A-Za-z.+:~]*\+homelab\.([0-9]+)-1\+(ubuntu26\.04|ubuntu24\.04|debian13)\z/
  server_build = pattern.match(version)
  agent_build = pattern.match(agent)
  abort 'Expected coordinated Debian package versions' unless server_build && agent_build && server_build.captures == agent_build.captures
  suffix = server_build[1]
end

root = Pathname(root)
gem_list = root / 'openvox-server/resources/ext/build-scripts/jruby-gem-list.txt'
gem_list_text = gem_list.read
abort 'Expected one public jruby-openssl dependency' unless gem_list_text.scan(/^jruby-openssl \S+$/).size == 1
gem_list_text = gem_list_text.sub(/^jruby-openssl \S+\n/, '')
installer = root / 'openvox-server/resources/ext/build-scripts/install-vendored-gems.sh'
installer_text = installer.read
install_after = 'install_gems "${DIR}/jruby-stdlib-gem-list.txt"'
abort 'Expected one JRuby stdlib installation' unless installer_text.scan(install_after).size == 1
installer_text = installer_text.sub(install_after, install_after + <<~'SH')

  # The coordinated snapshot supplies the OpenSSL implementation for all JRuby users.
  gem_install_jars=(ext/classpath-jars/{bcpkix,bcprov}-jdk18on-*.jar)
  java -cp "$(IFS=:; echo "${gem_install_jars[*]}"):puppet-server-release.jar" clojure.main -m puppetlabs.puppetserver.cli.gem --config jruby.conf -- install --local --ignore-dependencies --no-document "${DIR}/jruby-openssl.gem"
SH
ssl = root / 'jvm-ssl-utils/project.clj'
ssl_text = ssl.read
ssl_project = /\(defproject org.openvoxproject\/ssl-utils "([^"]+)"/
old = ssl_text.match(ssl_project)&.[](1)
abort 'Expected uncoordinated SSL project version' unless old && !old.include?('-homelab.')
local = old.delete_suffix('-SNAPSHOT') + '-homelab.' + suffix

server = root / 'openvox-server/project.clj'
text = server.read
needle = "[org.openvoxproject/ssl-utils \"#{old}\"]"
abort 'Expected one matching SSL dependency' unless text.scan(needle).size == 1
text = text.sub(needle, "[org.openvoxproject/ssl-utils \"#{local}\"]")

if version
  server_old = text.match(/\(defproject org.openvoxproject\/puppetserver "([^"]+)"/)&.[](1)
  abort 'Expected uncoordinated server project version' unless server_old && !server_old.include?('-homelab.')
  server_local = server_old.delete_suffix('-SNAPSHOT') + '-homelab.' + suffix
  abort 'EZbake self dependency changed' unless text.scan("[org.openvoxproject/puppetserver \"#{server_old}\"]").size == 2
  text = text.gsub('"' + server_old + '"', '"' + server_local + '"')

  config = root / 'openvox-server/resources/ext/ezbake.conf'
  config_text = config.read
  abort 'Agent dependency changed' unless config_text.scan('openvox-agent (>= 9.1.0)').size == 1
  config_text = config_text.sub('openvox-agent (>= 9.1.0)', "openvox-agent (= #{agent})")
end

# Validate both recipes before changing either; local coordinates cannot resolve a public SNAPSHOT.
ssl.write(ssl_text.sub(ssl_project, "(defproject org.openvoxproject/ssl-utils \"#{local}\""))
server.write(text)
config.write(config_text) if version
gem_list.write(gem_list_text)
installer.write(installer_text)
