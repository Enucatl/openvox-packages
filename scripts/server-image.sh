#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
release=${1:?Usage: server-image.sh RELEASE [--push|--prepare|--publish-prepared]}
mode=${2:-}
[[ -z $mode || $mode == --push || $mode == --prepare || $mode == --publish-prepared ]] || exit 2
export GH_REPO=${GH_REPO:-Enucatl/openvox-packages}
context=$(mktemp -d)
trap 'rm -rf "$context"' EXIT
tag=()
if [[ $release != latest ]]; then tag=("$release"); fi
gh release view "${tag[@]}" --json tagName,body,isDraft,isPrerelease > "$context/release.json"
jq -e '.isDraft == false and .isPrerelease == false' "$context/release.json" >/dev/null
if [[ $mode != --prepare ]]; then
  jq -e '.body | split("\n") | index("Acceptance: passed") != null' "$context/release.json" >/dev/null
fi
release=$(jq -r .tagName "$context/release.json")
[[ $release =~ ^resolute-[0-9]+$ ]] || { echo 'Expected an Ubuntu 26.04 package release' >&2; exit 1; }
mkdir -p "$context/dist" "$context/docker"
gh release download "$release" --pattern build-manifest.json --dir "$context/dist"
manifest="$context/dist/build-manifest.json"
agent=$(jq -er '.sources.openvox.package_version' "$manifest")
server=$(jq -er '.sources["openvox-server"].package_version' "$manifest")
[[ $agent == *-1+ubuntu26.04 && $server == *-1+ubuntu26.04 ]] || { echo 'Server image requires Ubuntu 26.04 packages' >&2; exit 1; }
version=$(jq -er '.sources["openvox-server"].base' "$manifest")
build=$(jq -er '.build' "$manifest")
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && $build =~ ^[0-9]+$ && $server == "$version+homelab.$build-1+ubuntu26.04" ]] || { echo 'Invalid server image version/build provenance' >&2; exit 1; }
owner=${GH_REPO%%/*}
repository="ghcr.io/${owner,,}/openvox-server"
image="$repository:$version-mldsa.$build"
revision=${GITHUB_SHA:-$(git rev-parse HEAD)}
if [[ $mode == --publish-prepared ]]; then
  jq -e --arg release "$release" --arg image "$image" --arg revision "$revision" \
    --arg checksum "$(sha256sum dist/server-image.tar | cut -d ' ' -f1)" --slurpfile packages "$manifest" \
    '.release == $release and .tag == $image and .revision == $revision and .sha256 == $checksum and .packages == $packages[0]' \
    dist/server-image-prepared.json >/dev/null
  docker load --input dist/server-image.tar
  [[ $(docker image inspect --format '{{.Id}}' "$image") == "$(jq -er .image_id dist/server-image-prepared.json)" ]]
else
  cp -R docker/server "$context/docker/"
  cp openvox-archive-keyring.asc "$context/"
  docker build --platform linux/amd64 --progress plain \
    --build-arg "APT_URL=https://github.com/$GH_REPO/releases/download/$release/" \
    --build-arg "AGENT_VERSION=$agent" --build-arg "SERVER_VERSION=$server" \
    --label "org.opencontainers.image.source=https://github.com/$GH_REPO" \
    --label "org.opencontainers.image.revision=$revision" \
    --label "org.opencontainers.image.version=$version-mldsa.$build" \
    --file "$context/docker/server/Dockerfile" --tag "$image" "$context"
  tests/server-image.sh "$image"
fi
if [[ $mode == --prepare ]]; then
  mkdir -p dist
  docker save --output dist/server-image.tar "$image"
  jq -n --arg release "$release" --arg image "$image" --arg revision "$revision" \
    --arg image_id "$(docker image inspect --format '{{.Id}}' "$image")" \
    --arg checksum "$(sha256sum dist/server-image.tar | cut -d ' ' -f1)" --slurpfile packages "$manifest" \
    '{release: $release, tag: $image, revision: $revision, image_id: $image_id, sha256: $checksum, packages: $packages[0]}' \
    > dist/server-image-prepared.json
fi
if [[ $mode == --push || $mode == --publish-prepared ]]; then
  docker push "$image"
  digest=$(docker image inspect --format '{{index .RepoDigests 0}}' "$image")
  [[ $digest == "$repository@sha256:"* ]] || { echo 'Published image digest missing' >&2; exit 1; }
  tags=("$image")
  latest=$(gh release view --json tagName --jq .tagName)
  if [[ $release == "$latest" ]]; then
    docker tag "$image" "$repository:$version"
    docker push "$repository:$version"
    docker tag "$image" "$repository:latest"
    docker push "$repository:latest"
    tags+=("$repository:$version" "$repository:latest")
  fi
  mkdir -p evidence/server-image
  jq -n --arg image "$digest" --arg tag "$image" --arg release "$release" \
    --arg version "$version" --argjson tags "$(printf '%s\n' "${tags[@]}" | jq -R . | jq -s .)" \
    --arg revision "$revision" --slurpfile packages "$manifest" \
    '{image: $image, tag: $tag, tags: $tags, upstream_version: $version, package_release: $release, image_revision: $revision, packages: $packages[0]}' \
    > evidence/server-image/server-image.json
  gh release upload "$release" evidence/server-image/server-image.json --clobber
  if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
    printf 'OpenVox server image: %s\n\nPackage release: %s\n' "$digest" "$release" >> "$GITHUB_STEP_SUMMARY"
  fi
fi
