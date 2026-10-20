#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for target in ubuntu26.04 debian13; do
  TARGET=$target bash -c '
    source scripts/native-client-target.sh
    [[ $CURL_VERSION == *+homelab.1+$TARGET ]]
    [[ $IPALIB_VERSION == *+homelab.1+$TARGET ]]
    dpkg --compare-versions "$CURL_VERSION" gt "$CURL_SOURCE_VERSION"
    dpkg --compare-versions "$IPALIB_VERSION" gt "$IPALIB_SOURCE_VERSION"
    dpkg --compare-versions "$CURL_SOURCE_VERSION+security1" gt "$CURL_VERSION"
  '
  awk '/Pin-Priority:/ && $2 > 500 {exit 1}' "apt/native-client-$target.pref"
  grep -F "Pin: version *+$target" "apt/native-client-$target.pref" >/dev/null
done
if TARGET=ubuntu24.04 bash -c 'source scripts/native-client-target.sh' >/dev/null 2>&1; then
  echo 'Unsupported native target unexpectedly accepted' >&2
  exit 1
fi
bash -n scripts/*native-client*.sh
if grep -Fx 'Acceptance: passed' scripts/publish-native-client.sh; then
  echo 'Native release would be mistaken for a coordinated release' >&2
  exit 1
fi
printf '%s\n' 'Native target versions, security update ordering and preference isolation passed'
