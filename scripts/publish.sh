#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${GH_REPO:?}" "${BUILD_NUMBER:?}" "${AGENT_VERSION:?}" "${SERVER_VERSION:?}"
tag="resolute-$BUILD_NUMBER"
# A failure retrieving an existing latest release must not be treated as an empty archive.
gh api --paginate --slurp "repos/$GH_REPO/releases" | jq 'add' > /tmp/openvox-releases.json
if jq -e 'any(.[]; .draft == false and ((.body // "") | contains("Acceptance: passed")))' /tmp/openvox-releases.json >/dev/null; then
  previous=$(gh api "repos/$GH_REPO/releases/latest" --jq .tag_name)
  gh api "repos/$GH_REPO/releases/tags/$previous" --jq .body | grep -Fx 'Acceptance: passed'
  gh release download "$previous" --pattern build-manifest.json --output /tmp/openvox-previous.json
  for kind in agent server; do
    if [[ $kind == agent ]]; then repo=openvox; current=$AGENT_VERSION; else repo=openvox-server; current=$SERVER_VERSION; fi
    old=$(jq -r --arg repo "$repo" '.sources[$repo].package_version' /tmp/openvox-previous.json)
    dpkg --compare-versions "$current" gt "$old"
    gh release download "$previous" --pattern "openvox-${kind}_${old}_*.deb" --dir dist
    printf 'PREVIOUS_%s=%s\n' "${kind^^}" "$old" >> "$GITHUB_ENV"
  done
fi
scripts/archive.sh
gh release create "$tag" --draft --title "Ubuntu 26.04 build $BUILD_NUMBER" --notes-file RELEASE-NOTES.md dist/*.deb dist/Packages dist/Packages.gz dist/Release dist/InRelease dist/Release.gpg dist/build-manifest.json dist/SHA256SUMS
id=$(gh release view "$tag" --json databaseId --jq .databaseId)
gh api --method PATCH "repos/$GH_REPO/releases/$id" -F draft=false -f make_latest=false >/dev/null
printf 'CANDIDATE_TAG=%s\nCANDIDATE_URL=https://github.com/%s/releases/download/%s/\n' "$tag" "$GH_REPO" "$tag" >> "$GITHUB_ENV"
