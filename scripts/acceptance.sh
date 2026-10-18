#!/bin/bash
set -euo pipefail
# Run in a disposable Docker container; URL must be a published candidate or latest.
: "${AGENT_VERSION:?Expected candidate agent version required}"
: "${SERVER_VERSION:?Expected candidate server version required}"
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
url=${1:?Usage: acceptance.sh REPOSITORY_URL PUBLIC_KEY [PREVIOUS_AGENT_VERSION PREVIOUS_SERVER_VERSION]}
key=${2:?Public archive key required}
[[ $url == https://* ]] || { echo 'An anonymous HTTPS APT URL is required' >&2; exit 2; }
context=$(mktemp -d)
image="openvox-package-acceptance:${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
container="openvox-package-acceptance-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
mkdir -p "$root/evidence/acceptance"
stage='prepare acceptance image'
# shellcheck disable=SC2317 # Invoked by the EXIT trap.
cleanup() {
  code=$?
  trap - EXIT
  printf 'stage=%s\nexit_code=%s\n' "$stage" "$code" > "$root/evidence/acceptance/host-status.txt"
  if (( code != 0 )); then
    printf 'Acceptance failed during %s (exit %s); see acceptance diagnostics.\n' "$stage" "$code" >&2
  fi
  "$root/scripts/acceptance-diagnostics.sh" "$container" "$root/evidence/acceptance" || true
  docker rm -f "$container" >/dev/null 2>&1 || true
  docker image rm "$image" >/dev/null 2>&1 || true
  rm -rf "$context"
  exit "$code"
}
trap cleanup EXIT
cp -R "$root/tests/acceptance/." "$context/"
cp "$key" "$context/archive-key.asc"
cp -R "$root/sources/vault/lib" "$context/vault-module"
stage='build acceptance image and install packages'
docker build --progress plain --build-arg "APT_URL=$url" --build-arg "AGENT_VERSION=$AGENT_VERSION" --build-arg "SERVER_VERSION=$SERVER_VERSION" --build-arg "PREVIOUS_AGENT=${3:-}" --build-arg "PREVIOUS_SERVER=${4:-}" -t "$image" "$context" 2>&1 | tee "$root/evidence/acceptance/build.log"
stage='create acceptance container'
docker create --name "$container" --network none --cap-drop ALL --security-opt no-new-privileges --memory 3g "$image" >/dev/null
stage='run acceptance setup and lifecycle'
timeout 1200 docker start -a "$container"
[[ $(docker inspect --format '{{.State.Running}}' "$container") == false ]]
exit "$(docker inspect --format '{{.State.ExitCode}}' "$container")"
