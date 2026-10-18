#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
: "${AGENT_VERSION:?Set the complete Debian agent version}"
[[ $AGENT_VERSION =~ ^[0-9][0-9A-Za-z.+:~]*\+homelab\.[0-9]+-1\+ubuntu26\.04$ ]] || {
  echo "Unexpected AGENT_VERSION: $AGENT_VERSION" >&2
  exit 1
}
export OPENVOX_AGENT_VERSION=${AGENT_VERSION%-1+ubuntu26.04}
export BUNDLE_PATH=${BUNDLE_PATH:-${RUNNER_TEMP:-/tmp}/openvox-packages-bundle}
cd sources/openvox
bundle install --jobs 4
cd packaging
bundle exec vanagon build openvox-agent ubuntu-26.04-amd64 --engine docker --preserve never
mapfile -t packages < <(find output -type f -name 'openvox-agent*_amd64.deb')
[[ ${#packages[@]} == 1 ]] || { echo 'Expected exactly one agent .deb' >&2; exit 1; }
[[ $(dpkg-deb -f "${packages[0]}" Package) == openvox-agent ]]
[[ $(dpkg-deb -f "${packages[0]}" Architecture) == amd64 ]]
[[ $(dpkg-deb -f "${packages[0]}" Version) == "$AGENT_VERSION" ]]
mkdir -p "$root/dist"
cp "${packages[0]}" "$root/dist/openvox-agent_${AGENT_VERSION}_amd64.deb"
