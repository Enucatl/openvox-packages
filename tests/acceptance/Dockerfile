FROM ubuntu:26.04@sha256:c098726dd9b9733f3e885f8de0ef375206a311b0a317eadc40d347b1115fb944
ENV DEBIAN_FRONTEND=noninteractive
ARG APT_URL
ARG AGENT_VERSION
ARG SERVER_VERSION
ARG PREVIOUS_AGENT
ARG PREVIOUS_SERVER
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl gnupg openjdk-25-jdk-headless openssl && rm -rf /var/lib/apt/lists/*
# Exercise installation over an upstream agent; fork packages must replace it.
RUN curl -fsSLo /tmp/openvox-release.deb https://apt.voxpupuli.org/openvox9-release-ubuntu26.04.deb && dpkg -i /tmp/openvox-release.deb && apt-get update && apt-get install -y --no-install-recommends openvox-agent=9.1.0-1+ubuntu26.04 && test "$(dpkg-query -W -f='${Version}' openvox-agent)" = 9.1.0-1+ubuntu26.04 && for source in /etc/apt/sources.list.d/*; do if grep -q apt.voxpupuli.org "$source"; then mv "$source" "$source.disabled"; fi; done && rm -rf /var/lib/apt/lists/*
COPY --chmod=0644 archive-key.asc /usr/share/keyrings/openvox-homelab.asc
RUN printf 'deb [signed-by=/usr/share/keyrings/openvox-homelab.asc] %s ./\n' "$APT_URL" > /etc/apt/sources.list.d/openvox.sources.list
# The URL is public: no GitHub token or HTTP credentials enter this image.
RUN apt-get update -o APT::Update::Error-Mode=any && apt-get install -y --no-install-recommends openvox-server
COPY apt-check.sh /tmp/apt-check.sh
RUN AGENT_VERSION="$AGENT_VERSION" SERVER_VERSION="$SERVER_VERSION" /tmp/apt-check.sh "$PREVIOUS_AGENT" "$PREVIOUS_SERVER"
COPY . /test/
RUN curl -fsSLo /tmp/vault.zip https://releases.hashicorp.com/vault/2.2.0/vault_2.2.0_linux_amd64.zip && echo '05d78b0ac842ca7c522fc297df91527cd43c15420c4c5c0a969d48a7b0ff7b6d  /tmp/vault.zip' | sha256sum -c - && cd /usr/local/bin && jar xf /tmp/vault.zip vault && chmod 755 vault && rm /tmp/vault.zip
COPY vault-module/ /test/code/environments/production/modules/vault_secrets/lib/
WORKDIR /test
RUN chmod 755 /usr/local/bin/vault && ln -s /opt/puppetlabs/server/apps/puppetserver/puppet-server-release.jar server.jar && ln -s /opt/puppetlabs/server/data/puppetserver/java.security.mldsa java.security.mldsa && test -f java.security.mldsa && javac StartupProbe.java
# Configure fixtures at build time without changing package ownership.
RUN <<'CONFIGURE'
# systemd creates RuntimeDirectory on service startup; foreground containers need it too.
set -eu
install -d -o puppet -g puppet /var/run/puppetlabs/puppetserver
mkdir -p /test/active /test/code/environments/production/manifests
printf "file { '/test/applied-client': ensure => file, content => 'mldsa-catalog-applied' }\n" > /test/code/environments/production/manifests/site.pp
cat > /etc/puppetlabs/puppet/puppet.conf <<'EOF'
[main]
certname = server
ssldir = /test/active/ssl
hostcert = /test/active/server-chain.pem
hostprivkey = /test/active/server.key
hostpubkey = /test/active/server.pub
localcacert = /test/active/ca-chain.pem
hostcrl = /test/active/host.crl
cadir = /test/active/ca
autosign = /test/autosign.conf
codedir = /test/code
ca_ttl = 1h
EOF
cat > /etc/puppetlabs/puppetserver/conf.d/webserver.conf <<'EOF'
webserver: {
  ssl-host: "127.0.0.1"
  ssl-port: 8140
  client-auth: want
  ssl-cert: /test/active/server-chain.pem
  ssl-key: /test/active/server.key
  ssl-ca-cert: /test/active/ca-chain.pem
  ssl-crl-path: /test/active/host.crl
  ssl-protocols: [TLSv1.3]
}
EOF
cat >> /etc/puppetlabs/puppetserver/conf.d/puppetserver.conf <<'EOF'

jruby-puppet: { max-active-instances: 1, server-code-dir: /test/code }
EOF
cat > /etc/puppetlabs/puppetserver/conf.d/ca.conf <<'EOF'
certificate-authority: {
  allow-auto-renewal: true
  auto-renewal-cert-ttl: "1h"
}
EOF
chown -R puppet:puppet /test
CONFIGURE
USER puppet
CMD ["/bin/sh", "/test/run.sh"]
