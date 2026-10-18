#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p sources
for repo in "$@"; do
  sha=$(awk -v repo="$repo" '$1 == repo {print $2}' dist/source-heads.tsv)
  [[ $sha =~ ^[0-9a-f]{40}$ ]]
  git clone --no-checkout "https://github.com/Enucatl/$repo.git" "sources/$repo"
  git -C "sources/$repo" checkout --detach "$sha"
  git -C "sources/$repo" submodule update --init --recursive
  case "$repo" in
    openvox|openvox-server)
      git -C "sources/$repo" fetch "https://github.com/OpenVoxProject/$repo.git" '+refs/tags/*:refs/tags/*'
      ;;
  esac
done
