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
COPY vault-module/ /etc/puppetlabs/code/environments/production/modules/vault_secrets/lib/
WORKDIR /test
RUN chmod 755 /usr/local/bin/vault && mv setup.sh vault-setup.sh && mkdir -p vault && mv vault-setup.sh vault-poc.rb vault/ && ln -s /opt/puppetlabs/server/apps/puppetserver/puppet-server-release.jar server.jar && ln -s /opt/puppetlabs/server/data/puppetserver/java.security.mldsa java.security.mldsa && test -f java.security.mldsa && javac StartupProbe.java && mkdir -p /test/active /etc/puppetlabs/code/environments/production/manifests /var/run/puppetlabs/puppetserver && chown -R puppet:puppet /test /etc/puppetlabs/puppet /etc/puppetlabs/puppetserver /etc/puppetlabs/code /var/run/puppetlabs/puppetserver /var/log/puppetlabs/puppetserver /opt/puppetlabs/server/data/puppetserver
USER puppet
CMD ["/bin/sh", "/test/run.sh"]
