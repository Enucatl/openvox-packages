#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
source scripts/target.sh
: "${AGENT_VERSION:?Set the complete Debian agent version}"
package="dist/openvox-agent_${AGENT_VERSION}_amd64.deb"
[[ -f $package ]]
docker run --rm --platform linux/amd64 -e DEBIAN_FRONTEND=noninteractive \
  -e AGENT_VERSION -v "$root:/work:ro" -w /work/sources/openvox "$BASE_IMAGE" sh -ec '
    apt-get update
    apt-get install -y --no-install-recommends "/work/dist/openvox-agent_${AGENT_VERSION}_amd64.deb"
    env -u OPENSSL_CONF -u RUBYOPT -u LD_PRELOAD /opt/puppetlabs/puppet/bin/ruby spec/integration/ssl/mldsa_self_check.rb
  ' | tee dist/agent-test.log
