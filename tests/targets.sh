#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
mkdir -p "$build/scripts" "$build/bin" "$build/sources/openvox/packaging/output"
cp "$root/scripts/target.sh" "$root/scripts/build-agent.sh" "$build/scripts/"
touch "$build/sources/openvox/packaging/output/openvox-agent_fixture_amd64.deb"
touch "$build/sources/openvox/packaging/output/openvox-agent-dbgsym_fixture_amd64.deb"
cat > "$build/bin/bundle" <<'BUNDLE'
#!/usr/bin/env bash
printf '%s %s\n' "$OPENVOX_AGENT_VERSION" "$*" >> "$BUNDLE_LOG"
BUNDLE
cat > "$build/bin/dpkg-deb" <<'DPKG'
#!/usr/bin/env bash
case "$3" in
  Package) echo openvox-agent ;;
  Architecture) echo amd64 ;;
  Version) echo "$AGENT_VERSION" ;;
  *) exit 1 ;;
esac
DPKG
chmod +x "$build/bin/"*
export PATH="$build/bin:$PATH" BUNDLE_LOG="$build/bundle.log"

unset TARGET
source "$root/scripts/target.sh"
[[ $TARGET == ubuntu26.04 && $PLATFORM == ubuntu-26.04-amd64 ]]
for TARGET in ubuntu26.04 debian13; do
  source "$root/scripts/target.sh"
  [[ $BASE_IMAGE == *@sha256:* && $UPSTREAM_AGENT_VERSION == "9.1.0-1+$TARGET" ]]
  [[ $UPSTREAM_RELEASE == "openvox9-release-$TARGET.deb" ]]
  export AGENT_VERSION="9.1.0+homelab.42-1+$TARGET"
  : > "$BUNDLE_LOG"
  bash "$build/scripts/build-agent.sh"
  grep -Fx "9.1.0+homelab.42 exec vanagon build openvox-agent $PLATFORM --engine docker --preserve never" "$BUNDLE_LOG"
  [[ -f "$build/dist/openvox-agent_${AGENT_VERSION}_amd64.deb" ]]
done

: > "$BUNDLE_LOG"
if TARGET=debian13 AGENT_VERSION=9.1.0+homelab.42-1+ubuntu26.04 bash "$build/scripts/build-agent.sh" 2>/dev/null; then
  echo 'Accepted an agent version for another target' >&2
  exit 1
fi
[[ ! -s $BUNDLE_LOG ]]
for TARGET in ubuntu24.04 debian12; do
  if TARGET=$TARGET bash -c 'source "$1"' bash "$root/scripts/target.sh" 2>/dev/null; then
    echo 'Accepted an unsupported target' >&2
    exit 1
  fi
done
echo 'Package target and agent build checks passed'
