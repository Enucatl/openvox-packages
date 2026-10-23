#!/bin/sh
set -eu
container=${1:?Container required}
destination=${2:?Diagnostics destination required}
mkdir -p "$destination"
# Only named diagnostic files may leave the container; state and Vault responses contain credentials.
for path in status.txt scope.txt versions.txt jruby-openssl.log generate.log crls.log vault-setup.log lifecycle.log results.txt; do
  docker cp "$container:/test/$path" "$destination/$path" 2>/dev/null || true
done
for variant in RSA ML-DSA-44; do
  for action in import setup; do
    label="$variant-lifecycle"
    if [ "$action" = setup ]; then label="$variant-setup-lifecycle"; fi
    mkdir -p "$destination/$label"
    for name in "$action.log" startup.log service.log agent-first.log agent-second.log agent-good.log agent-denied.log agent-replacement.log tls-negotiation.json revocation-error.txt; do
      path="$label/$name"
      docker cp "$container:/test/$path" "$destination/$path" 2>/dev/null || true
    done
  done
done
for name in puppetserver.log puppetserver-daemon.log; do
  docker cp "$container:/var/log/puppetlabs/puppetserver/$name" "$destination/package-$name" 2>/dev/null || true
done
