#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p sources
for repo in "$@"; do
  sha=$(jq -er --arg repo "$repo" '.sources[$repo].sha' dist/build-manifest.json)
  [[ $sha =~ ^[0-9a-f]{40}$ ]]
  [[ $(git rev-parse "HEAD:sources/$repo") == "$sha" && $(git rev-parse ":sources/$repo") == "$sha" ]] || {
    echo "Source snapshot does not match the committed submodule: $repo" >&2
    exit 1
  }
  git submodule update --init --recursive --checkout -- "sources/$repo"
  [[ $(git -C "sources/$repo" rev-parse HEAD) == "$sha" ]]
  case "$repo" in
    openvox|openvox-server)
      git -C "sources/$repo" fetch "https://github.com/OpenVoxProject/$repo.git" '+refs/tags/*:refs/tags/*'
      ;;
  esac
done
