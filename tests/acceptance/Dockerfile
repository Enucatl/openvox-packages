ARG BASE_IMAGE
FROM ${BASE_IMAGE} AS prerequisites
ENV DEBIAN_FRONTEND=noninteractive
ARG UPSTREAM_RELEASE
ARG UPSTREAM_AGENT_VERSION
# Refresh distro packages daily, retaining the cache between same-day releases.
ARG PREREQUISITES_DATE
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl gnupg openjdk-25-jdk-headless openssl && rm -rf /var/lib/apt/lists/*
# Exercise installation over an upstream agent; fork packages must replace it.
RUN curl -fsSLo /tmp/openvox-release.deb "https://apt.voxpupuli.org/$UPSTREAM_RELEASE" && dpkg -i /tmp/openvox-release.deb && apt-get update && apt-get install -y --no-install-recommends "openvox-agent=$UPSTREAM_AGENT_VERSION" && test "$(dpkg-query -W -f='${Version}' openvox-agent)" = "$UPSTREAM_AGENT_VERSION" && for source in /etc/apt/sources.list.d/*; do if grep -q apt.voxpupuli.org "$source"; then mv "$source" "$source.disabled"; fi; done && rm -rf /var/lib/apt/lists/*
FROM prerequisites AS acceptance
ARG TARGET
ARG ACCEPTANCE_GROUP=all
ENV TARGET=${TARGET} ACCEPTANCE_GROUP=${ACCEPTANCE_GROUP}
ARG APT_URL
ARG AGENT_VERSION
ARG SERVER_VERSION
ARG PREVIOUS_AGENT
ARG PREVIOUS_SERVER
COPY --chmod=0644 archive-key.asc /usr/share/keyrings/openvox-homelab.asc
COPY --chmod=0644 openvox.pref /etc/apt/preferences.d/openvox-homelab
RUN printf 'deb [signed-by=/usr/share/keyrings/openvox-homelab.asc] %s ./\n' "$APT_URL" > /etc/apt/sources.list.d/openvox.sources.list
# The URL is public: no GitHub token or HTTP credentials enter this image.
RUN apt-get update -o APT::Update::Error-Mode=any && apt-get install -y --no-install-recommends openvox-server
COPY apt-check.sh /tmp/apt-check.sh
RUN TARGET="$TARGET" AGENT_VERSION="$AGENT_VERSION" SERVER_VERSION="$SERVER_VERSION" /tmp/apt-check.sh "$PREVIOUS_AGENT" "$PREVIOUS_SERVER"
COPY . /test/
COPY --from=hashicorp/vault:2.2.0@sha256:e0acd3c681bdf57f002d7214e5d050b876e1704678005c6b0406dd96a65be919 /bin/vault /usr/local/bin/vault
COPY vault-module/ /test/code/environments/production/modules/vault_secrets/lib/
WORKDIR /test
RUN ln -s /opt/puppetlabs/server/apps/puppetserver/puppet-server-release.jar server.jar && ln -s /opt/puppetlabs/server/data/puppetserver/java.security.mldsa java.security.mldsa && test -f java.security.mldsa && javac StartupProbe.java
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
