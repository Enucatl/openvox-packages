#!/bin/sh
set -eu
cd /test
umask 077
stage='record installed versions'
log=versions.txt
finish() {
  code=$?
  trap - EXIT
  printf 'stage=%s\nexit_code=%s\n' "$stage" "$code" > status.txt
  if [ "$code" -ne 0 ]; then
    printf 'Acceptance failed during %s (exit %s); last output from %s:\n' "$stage" "$code" "$log" >&2
    tail -80 "$log" >&2 || true
    if [ "$stage" = lifecycle ]; then
      for path in RSA-lifecycle/startup.log RSA-lifecycle/service.log ML-DSA-44-lifecycle/startup.log ML-DSA-44-lifecycle/service.log RSA-setup-lifecycle/setup.log RSA-setup-lifecycle/startup.log RSA-setup-lifecycle/service.log ML-DSA-44-setup-lifecycle/setup.log ML-DSA-44-setup-lifecycle/startup.log ML-DSA-44-setup-lifecycle/service.log; do
        if [ -f "$path" ]; then
          printf '\n--- %s ---\n' "$path" >&2
          tail -40 "$path" >&2
        fi
      done
    fi
  fi
  if [ -f /test/vault-state/vault.pid ]; then kill "$(cat /test/vault-state/vault.pid)" || true; fi
  exit "$code"
}
trap finish EXIT
echo 'Installed fork Debian packages; no Ruby library or server JAR overlays.' > scope.txt
{ dpkg-query -W openvox-agent openvox-server openjdk-25-jre-headless; java -version; vault version; sha256sum server.jar /usr/local/bin/vault; } > versions.txt 2>&1
stage='installed JRuby OpenSSL'; log=jruby-openssl.log
/opt/puppetlabs/bin/puppetserver ruby /test/jruby-openssl.rb > "$log" 2>&1
stage='generate RSA fixtures'; log=generate.log
sh generate.sh > "$log" 2>&1
stage='generate RSA CRLs'; log=crls.log
sh crls.sh > "$log" 2>&1
stage='Vault hierarchy and certificate authentication'; log=vault-setup.log
VAULT_POC_DIR=/test/vault-state KEEP_VAULT=true /opt/puppetlabs/puppet/bin/ruby /test/vault-poc.rb > vault-setup.log 2>&1
stage='capture installed configuration'; log=versions.txt
printf 'client\ngood\n' > autosign.conf
mkdir config-evidence
cp -R /etc/puppetlabs/puppetserver/conf.d /etc/puppetlabs/puppetserver/services.d config-evidence/
cp /etc/puppetlabs/puppet/puppet.conf config-evidence/
stage=lifecycle; log=lifecycle.log
/opt/puppetlabs/puppet/bin/ruby lifecycle.rb > lifecycle.log 2>&1
cat results.txt
stage=complete
