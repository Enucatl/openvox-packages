#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
: "${AGENT_VERSION:?Set the complete Debian agent version}"
package="dist/openvox-agent_${AGENT_VERSION}_amd64.deb"
[[ -f $package ]]
export BUNDLE_PATH=${BUNDLE_PATH:-${RUNNER_TEMP:-/tmp}/openvox-packages-bundle}
cd sources/openvox
bundle install --jobs 4
bundle exec rake parallel:spec
cd "$root"
docker run --rm --platform linux/amd64 -e DEBIAN_FRONTEND=noninteractive \
  -e AGENT_VERSION -v "$root:/work:ro" -w /work/sources/openvox ubuntu:26.04 sh -ec '
    apt-get update
    apt-get install -y --no-install-recommends "/work/dist/openvox-agent_${AGENT_VERSION}_amd64.deb"
    /opt/puppetlabs/puppet/bin/ruby spec/integration/ssl/mldsa_self_check.rb
  '
