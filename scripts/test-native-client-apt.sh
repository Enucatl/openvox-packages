#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/native-client-target.sh
docker run --rm -i --platform linux/amd64 --mount "type=bind,src=$PWD,dst=/repo,readonly" \
  -e CURL_VERSION -e IPALIB_VERSION -e TARGET "$BASE_IMAGE" bash -s <<'CHECK'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
install -d /etc/apt/keyrings
cp "/repo/apt/native-client-$TARGET.pref" /etc/apt/preferences.d/native-client
cat > /etc/apt/sources.list.d/native-client.sources <<'SOURCE'
Types: deb
URIs: file:/repo/dist/
Suites: ./
Architectures: amd64
Signed-By: /etc/apt/keyrings/openvox.asc
SOURCE
# The companion source must fail closed before its trusted key is installed.
if apt-get update -o APT::Update::Error-Mode=any -o Dir::Etc::sourcelist=sources.list.d/native-client.sources -o Dir::Etc::sourceparts=- >/tmp/missing-key.log 2>&1; then
  echo 'Archive unexpectedly accepted without signing key' >&2
  exit 1
fi
cp /repo/openvox-archive-keyring.asc /etc/apt/keyrings/openvox.asc
apt-get update -o APT::Update::Error-Mode=any
for package in curl libcurl4t64 python3-ipalib; do
  expected=$CURL_VERSION
  if [[ $package == python3-ipalib ]]; then expected=$IPALIB_VERSION; fi
  test "$(apt-cache policy "$package" | awk '/Candidate:/ {print $2}')" = "$expected"
done
apt-get install -y --no-install-recommends \
  "curl=$CURL_VERSION" "libcurl4t64=$CURL_VERSION" "python3-ipalib=$IPALIB_VERSION" openssl
python3 /repo/docker/curl/check.py
python3 /repo/docker/freeipa-client/check.py
CHECK
