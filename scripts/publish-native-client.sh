#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${GH_REPO:?}" "${GITHUB_SHA:?}" "${GITHUB_RUN_NUMBER:?}" "${GITHUB_RUN_ATTEMPT:?}"
tag="native-client-${GITHUB_RUN_NUMBER}-${GITHUB_RUN_ATTEMPT}"
ruby -rjson -rdigest <<'RUBY'
manifest = { 'coordinator_sha' => ENV.fetch('GITHUB_SHA'), 'targets' => %w[ubuntu26.04 debian13].to_h do |target|
  result = JSON.parse(File.read("dist/native-client-#{target}.json"))
  abort 'Native client checks failed' unless result.fetch('target') == target && result.fetch('checks').values.all? { |check| check == 'passed' }
  result.fetch('packages').each do |name, package|
    path = package.fetch('file')
    abort 'Invalid native package path' unless File.basename(path) == path && path.end_with?('.deb')
    abort "Changed native package: #{path}" unless Digest::SHA256.file("dist/#{path}").hexdigest == package.fetch('sha256')
  end
  [target, result]
end }
File.write('dist/native-client-manifest.json', JSON.pretty_generate(manifest) + "\n")
RUBY
cp apt/native-client-*.pref dist/
ARCHIVE_MANIFEST=native-client-manifest.json scripts/archive.sh
for target in ubuntu26.04 debian13; do
  TARGET=$target scripts/test-native-client-apt.sh
done
cat > dist/native-client-notes.md <<'NOTES'
Native FreeIPA client ML-DSA compatibility prerequisites for Ubuntu 26.04 and Debian 13 amd64.

Native client acceptance: passed

Installed curl Negotiate/TLS rejection and FreeIPA SPKI checks passed independently for both native targets. Fresh signed-APT tests rejected missing keys, selected matching target packages and reran the installed checks before publication. This companion archive does not replace or rebuild the accepted OpenVox agent/server pair.
NOTES
gh release create "$tag" --latest=false --target "$GITHUB_SHA" --title "Native FreeIPA client prerequisites $tag" \
  --notes-file dist/native-client-notes.md dist/*.deb dist/native-client-*.pref \
  dist/Packages dist/Packages.gz dist/Release dist/InRelease dist/Release.gpg \
  dist/native-client-manifest.json dist/SHA256SUMS
