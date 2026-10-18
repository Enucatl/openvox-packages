#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
# shellcheck disable=SC2317 # Called by EXIT trap.
cleanup() {
  GNUPGHOME="$work/gnupg" gpgconf --kill gpg-agent || true
  rm -rf "$work"
}
trap cleanup EXIT
export GNUPGHOME="$work/gnupg"
mkdir -m 700 "$GNUPGHOME"
export APT_SIGNING_PASSPHRASE=disposable-test-key
# The key exists only in this temporary directory and never becomes an artifact.
gpg --batch --pinentry-mode loopback --passphrase "$APT_SIGNING_PASSPHRASE" \
  --quick-generate-key 'Disposable archive selfcheck' rsa2048 sign 1d
APT_PRIMARY_FINGERPRINT=$(gpg --with-colons --list-secret-keys | awk -F: '$1 == "fpr" {print $10; exit}')
export APT_PRIMARY_FINGERPRINT
mkdir -p "$work/scripts" "$work/dist" "$work/package/DEBIAN" "$work/download" \
  "$work/apt/lists/partial" "$work/apt/cache/archives/partial" "$work/apt/parts"
cp "$root/scripts/archive.sh" "$work/scripts/"
cat > "$work/package/DEBIAN/control" <<'CONTROL'
Package: openvox-archive-selfcheck
Version: 1.0
Architecture: all
Maintainer: Selfcheck <nobody@example.invalid>
Description: Disposable APT signature and checksum test
CONTROL
printf 'archive test payload\n' > "$work/package/payload"
dpkg-deb --build "$work/package" "$work/dist/selfcheck.deb" >/dev/null
printf '{}\n' > "$work/dist/build-manifest.json"
bash "$work/scripts/archive.sh"
gpg --armor --export "$APT_PRIMARY_FINGERPRINT" > "$work/key.asc"
printf 'deb [signed-by=%s] file:%s ./\n' "$work/key.asc" "$work/dist" > "$work/apt/sources.list"
touch "$work/apt/status"
apt_options=(
  -o "Dir::Etc::sourcelist=$work/apt/sources.list"
  -o "Dir::Etc::sourceparts=$work/apt/parts"
  -o "Dir::State::lists=$work/apt/lists"
  -o "Dir::State::status=$work/apt/status"
  -o "Dir::Cache=$work/apt/cache"
  -o "Dir::Etc::trusted=$work/apt/no-trusted.gpg"
  -o "Dir::Etc::trustedparts=$work/apt/parts"
  -o "APT::Sandbox::User=$(id -un)"
  -o APT::Update::Error-Mode=any
)
update() {
  rm -rf "$work/apt/lists"
  mkdir -p "$work/apt/lists/partial"
  apt-get "${apt_options[@]}" update > "$work/update.log" 2>&1
}
reject_update() {
  if update; then
    echo "APT accepted $1" >&2
    cat "$work/update.log" >&2
    exit 1
  fi
  printf 'PASS: rejected %s\n' "$1"
}
update
(cd "$work/download" && apt-get "${apt_options[@]}" download openvox-archive-selfcheck=1.0)
printf 'PASS: verified signed archive and downloaded package\n'
cp -R "$work/dist" "$work/original"
printf 'modified package\n' >> "$work/dist/selfcheck.deb"
rm -f "$work/download/"*.deb
if (cd "$work/download" && apt-get "${apt_options[@]}" download openvox-archive-selfcheck=1.0) > "$work/package.log" 2>&1; then
  echo 'APT accepted a modified package' >&2
  exit 1
fi
printf 'PASS: rejected modified package\n'
cp "$work/original/selfcheck.deb" "$work/dist/selfcheck.deb"
printf '\nModified: yes\n' >> "$work/dist/Packages"
gzip -n -c "$work/dist/Packages" > "$work/dist/Packages.gz"
reject_update 'modified index'
cp "$work/original/Packages" "$work/original/Packages.gz" "$work/dist/"
# Alter authenticated cleartext without regenerating its detached signature.
sed -i 's/Origin: OpenVox-Homelab/Origin: Modified-Origin/' "$work/dist/InRelease"
reject_update 'modified InRelease signature'
cp "$work/original/InRelease" "$work/dist/"
# Model a latest-channel transition: valid metadata from build A, indexes from B.
sed -i 's/^Version: 1.0$/Version: 2.0/' "$work/package/DEBIAN/control"
dpkg-deb --build "$work/package" "$work/dist/selfcheck.deb" >/dev/null
bash "$work/scripts/archive.sh"
cp "$work/original/InRelease" "$work/dist/"
reject_update 'mixed release metadata and indexes'
cp "$work/original/Packages" "$work/original/Packages.gz" "$work/original/Release" "$work/dist/"
rm "$work/dist/InRelease" "$work/dist/Release.gpg"
reject_update 'unsigned archive'
cp "$work/original/InRelease" "$work/original/Release.gpg" "$work/dist/"
printf '' > "$work/key.asc"
reject_update 'untrusted signing key'
printf 'All isolated APT archive checks passed.\n'
