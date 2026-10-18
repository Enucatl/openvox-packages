#!/usr/bin/env bash
set -euo pipefail
image=${1:?server image required}
name="openvox-server-image-test-$$"
cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker volume rm "$name-ssl" "$name-ca" "$name-data" "$name-gems" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run --rm "$image" /bin/bash -eu -c '
  test "$(id -un)" = puppet
  test -z "$(find /etc/puppetlabs -type f -name "*.pem")"
  test -r /usr/share/openvox/build-manifest.json
  test -w /run/puppetlabs/puppetserver
  test -w /etc/puppetlabs/puppet/ssl
  test -w /opt/puppetlabs/server/data/puppetserver/server_data
  test "$(/opt/puppetlabs/bin/puppet config print vardir --section server --config /etc/puppetlabs/puppet/puppet.conf)" = /opt/puppetlabs/server/data/puppetserver/server_data
  /opt/puppetlabs/puppet/venv/bin/python -c "import click, cryptography.x509, hvac, yaml"
  "$JAVA_BIN" -version
'
java_args=$(docker image inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$image" | sed -n 's/^JAVA_ARGS=//p')
java_args=${java_args/-Xms2g -Xmx2g/-Xms256m -Xmx1024m -XX:ActiveProcessorCount=2}
if output=$(docker run --rm "$image" 2>&1); then
  echo 'An uninitialized server must refuse startup.' >&2
  exit 1
fi
grep -F 'Restore or explicitly initialize server identity before startup' <<<"$output" >/dev/null
mounts=(
  --mount "type=volume,src=$name-ssl,dst=/etc/puppetlabs/puppet/ssl"
  --mount "type=volume,src=$name-ca,dst=/etc/puppetlabs/puppetserver/ca"
  --mount "type=volume,src=$name-data,dst=/opt/puppetlabs/server/data/puppetserver/server_data"
  --mount "type=volume,src=$name-gems,dst=/opt/puppetlabs/server/data/puppetserver/jruby-gems"
)
# Prepare a disposable RSA identity explicitly; startup never initializes it.
docker run --rm --hostname server-image.test "${mounts[@]}" "$image" \
  /opt/puppetlabs/bin/puppetserver ca setup --config /etc/puppetlabs/puppet/puppet.conf
identity=$(docker run --rm --hostname server-image.test "${mounts[@]}" "$image" \
  sha256sum /etc/puppetlabs/puppet/ssl/private_keys/server-image.test.pem /etc/puppetlabs/puppetserver/ca/ca_key.pem)
start() {
  docker run -d --name "$name" --hostname server-image.test \
    --env "JAVA_ARGS=$java_args" \
    "${mounts[@]}" \
    "$image" >/dev/null
  if ! docker exec -i "$name" /opt/puppetlabs/puppet/bin/ruby -rnet/http -ropenssl <<'RUBY'
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 180
begin
  client = Net::HTTP.new('server-image.test', 8140, nil)
  client.use_ssl = true
  client.verify_mode = OpenSSL::SSL::VERIFY_PEER
  client.ca_file = '/etc/puppetlabs/puppet/ssl/certs/ca.pem'
  client.open_timeout = 2
  client.read_timeout = 5
  response = client.get('/puppet-ca/v1/certificate/ca')
  raise "CA endpoint returned #{response.code}" unless response.code == '200'
  cert = OpenSSL::X509::Certificate.new(response.body)
  raise 'Default identity is not RSA' unless cert.public_key.is_a?(OpenSSL::PKey::RSA)
rescue StandardError
  raise if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
  sleep 2
  retry
end
RUBY
  then
    docker logs "$name" >&2
    return 1
  fi
}
stop() {
  docker stop --time 30 "$name" >/dev/null
  test "$(docker inspect --format '{{.State.ExitCode}}' "$name")" != 137
  docker rm "$name" >/dev/null
}
start
if docker inspect --format '{{range .Mounts}}{{println .Destination}}{{end}}' "$name" | grep -Fx /opt/puppetlabs/server/data/puppetserver; then
  echo 'Persistent state must not cover image-owned policy or vendored gems.' >&2
  exit 1
fi
test "$(docker exec "$name" sha256sum /etc/puppetlabs/puppet/ssl/private_keys/server-image.test.pem /etc/puppetlabs/puppetserver/ca/ca_key.pem)" = "$identity"
docker exec "$name" ps -eo user,args | grep -F 'puppet' | grep -F '/usr/lib/jvm/java-25-openjdk-amd64/bin/java' >/dev/null
docker logs "$name" 2>&1 | grep -F 'OpenVox Server has successfully started' >/dev/null
stop
start
test "$(docker exec "$name" sha256sum /etc/puppetlabs/puppet/ssl/private_keys/server-image.test.pem /etc/puppetlabs/puppetserver/ca/ca_key.pem)" = "$identity"
stop
echo 'Server image: nonroot Java 25, helper imports, verified RSA HTTPS, stdout logs, graceful stop and identity-preserving recreation passed.'
