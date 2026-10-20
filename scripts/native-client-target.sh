#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/target.sh"
case "$TARGET" in
  ubuntu26.04) CURL_SOURCE_VERSION=8.18.0-1ubuntu2.8; IPALIB_SOURCE_VERSION=4.13.1-1 ;;
  debian13) CURL_SOURCE_VERSION=8.14.1-2+deb13u7; IPALIB_SOURCE_VERSION=4.12.4-1 ;;
  *) echo "Unsupported native client target: $TARGET" >&2; return 1 ;;
esac
CURL_VERSION=${CURL_SOURCE_VERSION}+homelab.1+${TARGET}
IPALIB_VERSION=${IPALIB_SOURCE_VERSION}+homelab.1+${TARGET}
export CURL_SOURCE_VERSION IPALIB_SOURCE_VERSION CURL_VERSION IPALIB_VERSION
