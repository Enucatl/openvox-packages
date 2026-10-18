#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == /opt/puppetlabs/server/apps/puppetserver/cli/apps/foreground ]]; then
  /opt/puppetlabs/bin/puppet config print hostcert hostprivkey localcacert cadir \
    --section server --config /etc/puppetlabs/puppet/puppet.conf --render-as json | \
    /opt/puppetlabs/puppet/bin/ruby -rjson -e '
      settings = JSON.parse(STDIN.read)
      paths = settings.values_at("hostcert", "hostprivkey", "localcacert") +
        %w[ca_crt.pem ca_key.pem].map { |name| File.join(settings.fetch("cadir"), name) }
      missing = paths.reject { |path| File.file?(path) && File.readable?(path) && File.size(path).positive? }
      abort "Restore or explicitly initialize server identity before startup; missing: #{missing.join(", ")}" unless missing.empty?
    '
fi
exec "$@"
