#!/usr/bin/env bash
# Shared package identity and installed-package test images.
TARGET=${TARGET:-ubuntu26.04}
case "$TARGET" in
  ubuntu26.04)
    PLATFORM=ubuntu-26.04-amd64
    BASE_IMAGE=ubuntu:26.04@sha256:c098726dd9b9733f3e885f8de0ef375206a311b0a317eadc40d347b1115fb944
    ;;
  debian13)
    PLATFORM=debian-13-amd64
    BASE_IMAGE=debian:13@sha256:bcf83fd8af414eda0c0a99d25a4e61dedd88e7aac7f7bc519d04555ff0c40ec5
    ;;
  *) echo "Unsupported package target: $TARGET" >&2; return 1 ;;
esac
UPSTREAM_RELEASE="openvox9-release-${TARGET}.deb"
UPSTREAM_AGENT_VERSION="9.1.0-1+$TARGET"
export TARGET PLATFORM BASE_IMAGE UPSTREAM_RELEASE UPSTREAM_AGENT_VERSION
