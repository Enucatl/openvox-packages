#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p sources dist
: "${GITHUB_RUN_NUMBER:?}"
: "${GITHUB_RUN_ATTEMPT:?}"
(( GITHUB_RUN_ATTEMPT < 1000 ))
BUILD_NUMBER=$((GITHUB_RUN_NUMBER * 1000 + GITHUB_RUN_ATTEMPT))
export BUILD_NUMBER
: > dist/source-heads.tsv
for repo in openvox jvm-ssl-utils openvox-server openvoxserver-ca vault; do
  read -r mode type sha _ < <(git ls-tree HEAD "sources/$repo")
  [[ $mode == 160000 && $type == commit && $sha =~ ^[0-9a-f]{40}$ ]]
  printf '%s\t%s\n' "$repo" "$sha" >> dist/source-heads.tsv
done
scripts/checkout-sources.sh openvox openvox-server
ruby <<'RUBY'
require 'json'
require 'open3'
manifest = { build: ENV.fetch('BUILD_NUMBER'), run: ENV.fetch('GITHUB_RUN_ID'), attempt: ENV.fetch('GITHUB_RUN_ATTEMPT'), sources: {} }
File.readlines('dist/source-heads.tsv').each do |line|
  repo, sha = line.split
  manifest[:sources][repo] = { sha: sha }
end
versions = {}
%w[openvox openvox-server].each do |repo|
  tag, status = Open3.capture2('git', '-C', "sources/#{repo}", 'describe', '--tags', '--match', '[0-9]*', '--abbrev=0')
  abort "No upstream release tag for #{repo}" unless status.success?
  tag = tag.strip
  abort "Unexpected tag #{tag}" unless tag.match?(/\A\d+\.\d+\.\d+\z/)
  count, status = Open3.capture2('git', '-C', "sources/#{repo}", 'rev-list', '--count', "#{tag}..HEAD")
  abort 'Cannot count source commits' unless status.success?
  version = "#{tag}+homelab.#{ENV.fetch('BUILD_NUMBER')}-1+ubuntu26.04"
  manifest[:sources][repo].merge!(base: tag, commits_since_tag: count.to_i, package_version: version)
  versions[repo == 'openvox' ? 'AGENT_VERSION' : 'SERVER_VERSION'] = version
end
File.write('dist/build-manifest.json', JSON.pretty_generate(manifest) + "\n")
File.open(ENV.fetch('GITHUB_ENV'), 'a') { |f| versions.each { |key, value| f.puts "#{key}=#{value}" }; f.puts "BUILD_NUMBER=#{ENV.fetch('BUILD_NUMBER')}" }
RUBY
