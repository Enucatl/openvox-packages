#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../dist"
: "${APT_PRIMARY_FINGERPRINT:?}"
: "${APT_SIGNING_PASSPHRASE:?}"
apt-ftparchive packages . > Packages
gzip -n -9 -c Packages > Packages.gz
# Generate outside the destination so Release cannot include its own stale hash.
metadata=$(mktemp)
trap 'rm -f "$metadata"' EXIT
apt-ftparchive -o APT::FTPArchive::Release::Origin=OpenVox-Homelab \
  -o APT::FTPArchive::Release::Label=OpenVox-Homelab \
  -o APT::FTPArchive::Release::Architectures='amd64 all' \
  -o APT::FTPArchive::Release::Description='ML-DSA OpenVox for Ubuntu 26.04, Ubuntu 24.04 and Debian 13' release . > "$metadata"
mv "$metadata" Release
for mode in clearsign detach-sign; do
  if [[ $mode == clearsign ]]; then output=InRelease; else output=Release.gpg; fi
  printf '%s' "$APT_SIGNING_PASSPHRASE" | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 \
    --local-user "$APT_PRIMARY_FINGERPRINT" --digest-algo SHA256 --armor --"$mode" --output "$output" Release
done
gpg --verify InRelease
gpg --verify Release.gpg Release
sha256sum ./*.deb Packages Packages.gz Release InRelease Release.gpg "${ARCHIVE_MANIFEST:-build-manifest.json}" > SHA256SUMS
