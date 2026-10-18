#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${GH_REPO:?}" "${BUILD_NUMBER:?}" "${AGENT_VERSION:?}" "${SERVER_VERSION:?}" "${GITHUB_SHA:?}"
tag="resolute-$BUILD_NUMBER"
# A failure retrieving an existing latest release must not be treated as an empty archive.
gh api --paginate --slurp "repos/$GH_REPO/releases" | jq 'add' > /tmp/openvox-releases.json
if jq -e 'any(.[]; .draft == false and ((.body // "") | contains("Acceptance: passed")))' /tmp/openvox-releases.json >/dev/null; then
  previous=$(gh api "repos/$GH_REPO/releases/latest" --jq .tag_name)
  gh api "repos/$GH_REPO/releases/tags/$previous" --jq .body | grep -Fx 'Acceptance: passed'
  gh release download "$previous" --pattern build-manifest.json --output /tmp/openvox-previous.json
  ruby <<'RUBY'
require 'json'
manifest = JSON.parse(File.read('dist/build-manifest.json'))
previous = JSON.parse(File.read('/tmp/openvox-previous.json'))
manifest['previous'] = {}
File.open('/tmp/openvox-previous-pairs.tsv', 'w') do |file|
  manifest.fetch('targets').each do |target, current|
    old = previous.fetch('targets', {})[target]
    old ||= previous if target == 'ubuntu26.04'
    next unless old
    manifest['previous'][target] = {}
    { 'agent' => 'openvox', 'server' => 'openvox-server' }.each do |kind, repo|
      version = old.fetch('sources').fetch(repo).fetch('package_version')
      candidate = current.fetch('sources').fetch(repo).fetch('package_version')
      abort 'Candidate version must exceed latest' unless system('dpkg', '--compare-versions', candidate, 'gt', version)
      manifest['previous'][target][kind] = version
      file.puts [kind, version].join("\t")
    end
  end
end
File.write('dist/build-manifest.json', JSON.pretty_generate(manifest) + "\n")
RUBY
  while read -r kind old; do
    gh release download "$previous" --pattern "openvox-${kind}_${old}_*.deb" --dir dist
  done < /tmp/openvox-previous-pairs.tsv
fi
cp apt/*.pref dist/
scripts/archive.sh
gh release create "$tag" --latest=false --target "$GITHUB_SHA" --title "Coordinated build $BUILD_NUMBER" --notes-file RELEASE-NOTES.md dist/*.deb dist/*.pref dist/Packages dist/Packages.gz dist/Release dist/InRelease dist/Release.gpg dist/build-manifest.json dist/SHA256SUMS
printf 'CANDIDATE_TAG=%s\nCANDIDATE_URL=https://github.com/%s/releases/download/%s/\n' "$tag" "$GH_REPO" "$tag" >> "$GITHUB_ENV"
if [[ -n ${GITHUB_OUTPUT:-} ]]; then
  printf 'tag=%s\nurl=https://github.com/%s/releases/download/%s/\n' "$tag" "$GH_REPO" "$tag" >> "$GITHUB_OUTPUT"
fi
