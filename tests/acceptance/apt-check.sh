#!/bin/bash
set -euo pipefail
agent=$(dpkg-query -W -f='${Version}' openvox-agent)
server=$(dpkg-query -W -f='${Version}' openvox-server)
[[ $agent == "${AGENT_VERSION:?Expected agent version required}" ]]
[[ $server == "${SERVER_VERSION:?Expected server version required}" ]]
dpkg-query -W -f='${Depends}' openvox-server | grep -F "openvox-agent (= $agent)"
: "${TARGET:?Expected package target required}"
for package in openvox-agent openvox-server; do
  policy=$(apt-cache policy "$package")
  expected=$agent
  [[ $package != openvox-server ]] || expected=$server
  [[ $policy == *"Candidate: $expected"$'\n'* ]]
  while read -r version priority rest; do
    if [[ $version == '***' ]]; then version=$priority; priority=$rest; fi
    [[ $version != *"+$TARGET" ]] || continue
    case $version in
      *+ubuntu26.04|*+ubuntu24.04|*+debian13)
        [[ $priority == -1 ]] || { echo "Wrong distribution is selectable: $package $version ($priority)" >&2; exit 1; } ;;
    esac
  done <<< "$policy"
done
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
