#!/bin/bash
set -euo pipefail
agent=$(dpkg-query -W -f='${Version}' openvox-agent)
server=$(dpkg-query -W -f='${Version}' openvox-server)
[[ $agent == "${AGENT_VERSION:?Expected agent version required}" ]]
[[ $server == "${SERVER_VERSION:?Expected server version required}" ]]
dpkg-query -W -f='${Depends}' openvox-server | grep -F "openvox-agent (= $agent)"
# Reject unsigned metadata rather than accidentally accepting cached indexes.
mv /usr/share/keyrings/openvox-homelab.asc /tmp/archive-key.asc
rm -rf /var/lib/apt/lists/*
if apt-get update -o APT::Update::Error-Mode=any; then
  echo 'APT accepted an archive without its trusted key' >&2
  exit 1
fi
mv /tmp/archive-key.asc /usr/share/keyrings/openvox-homelab.asc
apt-get update -o APT::Update::Error-Mode=any
if [[ -n ${1:-} || -n ${2:-} ]]; then
  [[ -n ${1:-} && -n ${2:-} ]]
  dpkg --compare-versions "$agent" gt "$1"
  dpkg --compare-versions "$server" gt "$2"
  # Keep the current server selected so this is an independent agent downgrade.
  if apt-get -s --allow-downgrades --no-remove install "openvox-agent=$1" "openvox-server=$server"; then
    echo 'APT accepted an incompatible independent agent downgrade' >&2
    exit 1
  fi
  apt-get install -y --allow-downgrades "openvox-agent=$1" "openvox-server=$2"
  [[ $(dpkg-query -W -f='${Version}' openvox-agent) == "$1" ]]
  [[ $(dpkg-query -W -f='${Version}' openvox-server) == "$2" ]]
  apt-get upgrade -y
  [[ $(dpkg-query -W -f='${Version}' openvox-agent) == "$agent" ]]
  [[ $(dpkg-query -W -f='${Version}' openvox-server) == "$server" ]]
fi
