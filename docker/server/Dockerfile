FROM ubuntu:26.04@sha256:c098726dd9b9733f3e885f8de0ef375206a311b0a317eadc40d347b1115fb944

ARG APT_URL
ARG AGENT_VERSION
ARG SERVER_VERSION
ENV DEBIAN_FRONTEND=noninteractive

COPY --chmod=0644 openvox-archive-keyring.asc /etc/apt/keyrings/openvox-archive-keyring.asc
RUN set -eu; \
    test "$(dpkg --print-architecture)" = amd64; \
    : "${APT_URL:?versioned signed APT release URL required}" "${AGENT_VERSION:?exact agent version required}" "${SERVER_VERSION:?exact server version required}"; \
    APT_URL=${APT_URL%/}; \
    case "$APT_URL" in https://github.com/Enucatl/openvox-packages/releases/download/*) ;; *) exit 1 ;; esac; \
    release=${APT_URL##*/}; \
    test -n "$release"; test "$release" != latest; \
    apt-get update -o APT::Update::Error-Mode=any; \
    apt-get install -y --no-install-recommends ca-certificates gnupg openjdk-25-jre-headless python3 tini; \
    test "$(gpg --show-keys --with-colons /etc/apt/keyrings/openvox-archive-keyring.asc | awk -F: '$1 == "pub" { primary = 1; next } primary && $1 == "fpr" { print $10; primary = 0 }')" = 775661C709ACE6F7C1CF0FF6C4B7528F03E0BB94; \
    printf 'deb [signed-by=/etc/apt/keyrings/openvox-archive-keyring.asc] %s ./\n' "$APT_URL" > /etc/apt/sources.list.d/openvox.list; \
    apt-get update -o APT::Update::Error-Mode=any; \
    apt-get install -y --no-install-recommends "openvox-agent=$AGENT_VERSION" "openvox-server=$SERVER_VERSION"; \
    test "$(dpkg-query -W -f='${Version}' openvox-agent)" = "$AGENT_VERSION"; \
    test "$(dpkg-query -W -f='${Version}' openvox-server)" = "$SERVER_VERSION"; \
    test -f /opt/puppetlabs/server/data/puppetserver/java.security.mldsa; \
    test -z "$(find /etc/puppetlabs -type f -name '*.pem')"; \
    install -d -o puppet -g puppet /run/puppetlabs/puppetserver /etc/puppetlabs/puppet/ssl /etc/puppetlabs/puppetserver/ca /opt/puppetlabs/server/data/puppetserver/server_data; \
    printf '\n[main]\nssldir = /etc/puppetlabs/puppet/ssl\ncadir = /etc/puppetlabs/puppetserver/ca\n' >> /etc/puppetlabs/puppet/puppet.conf; \
    sed -i 's|vardir = /opt/puppetlabs/server/data/puppetserver|vardir = /opt/puppetlabs/server/data/puppetserver/server_data|' /etc/puppetlabs/puppet/puppet.conf; \
    sed -i '/certificate-authority: {/a\    cadir: /etc/puppetlabs/puppetserver/ca' /etc/puppetlabs/puppetserver/conf.d/ca.conf; \
    sed -i 's|server-var-dir: /opt/puppetlabs/server/data/puppetserver|server-var-dir: /opt/puppetlabs/server/data/puppetserver/server_data|' /etc/puppetlabs/puppetserver/conf.d/puppetserver.conf; \
    chown puppet:puppet /etc/puppetlabs/puppet; \
    rm -rf /var/lib/apt/lists/* /root/.gnupg

COPY --from=ghcr.io/astral-sh/uv:0.13.1@sha256:4a1f3666816dafadd20ceb71eac9a7d56d7ef30279f7d64048519ab901ada336 /uv /usr/local/bin/uv
COPY docker/server/pyproject.toml docker/server/uv.lock /opt/openvox-helper-runtime/
COPY --chmod=0644 dist/build-manifest.json /usr/share/openvox/build-manifest.json
COPY --chmod=0755 docker/server/entrypoint.sh /usr/local/bin/openvox-server-entrypoint
RUN chmod 0755 /usr/share/openvox && \
    UV_PROJECT_ENVIRONMENT=/opt/puppetlabs/puppet/venv \
    uv sync --project /opt/openvox-helper-runtime --locked --no-dev --no-managed-python --no-cache

LABEL org.opencontainers.image.source="https://github.com/Enucatl/openvox-packages" \
      org.opencontainers.image.description="Fork OpenVox Server; persist /etc/puppetlabs/puppet/ssl, /etc/puppetlabs/puppetserver/ca, /etc/puppetlabs/code, /opt/puppetlabs/server/data/puppetserver/server_data and /opt/puppetlabs/server/data/puppetserver/jruby-gems; mount writable /run/puppetlabs/puppetserver and /var/log/puppetlabs/puppetserver"
ENV JAVA_BIN=/usr/lib/jvm/java-25-openjdk-amd64/bin/java \
    JAVA_ARGS="-Xms2g -Xmx2g -Djava.security.properties=/opt/puppetlabs/server/data/puppetserver/java.security.mldsa -Djdk.tls.client.SignatureSchemes=mldsa44,rsa_pss_rsae_sha256,rsa_pss_pss_sha256,ecdsa_secp256r1_sha256,ed25519,rsa_pkcs1_sha256 -Djdk.tls.server.SignatureSchemes=mldsa44,rsa_pss_rsae_sha256,rsa_pss_pss_sha256,ecdsa_secp256r1_sha256,ed25519,rsa_pkcs1_sha256 -Dorg.bouncycastle.jsse.client.SignatureSchemesCert=mldsa44,rsa_pss_rsae_sha256,rsa_pss_pss_sha256,ecdsa_secp256r1_sha256,ed25519,rsa_pkcs1_sha256 -Dorg.bouncycastle.jsse.server.SignatureSchemesCert=mldsa44,rsa_pss_rsae_sha256,rsa_pss_pss_sha256,ecdsa_secp256r1_sha256,ed25519,rsa_pkcs1_sha256" \
    USER=puppet HOME=/opt/puppetlabs/server/data/puppetserver/server_data \
    INSTALL_DIR=/opt/puppetlabs/server/apps/puppetserver \
    CONFIG=/etc/puppetlabs/puppetserver/conf.d \
    BOOTSTRAP_CONFIG=/etc/puppetlabs/puppetserver/services.d/,/opt/puppetlabs/server/apps/puppetserver/config/services.d/
EXPOSE 8140
USER puppet
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/local/bin/openvox-server-entrypoint"]
CMD ["/opt/puppetlabs/server/apps/puppetserver/cli/apps/foreground"]
