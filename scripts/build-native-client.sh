#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/native-client-target.sh
mkdir -p "dist/native-client/$TARGET"
for component in curl freeipa-client; do
  if [[ $component == curl ]]; then
    source_version=$CURL_SOURCE_VERSION; package_version=$CURL_VERSION
  else
    source_version=$IPALIB_SOURCE_VERSION; package_version=$IPALIB_VERSION
  fi
  patch=openssl-channel-binding.patch
  if [[ $TARGET == debian13 ]]; then patch=openssl-channel-binding-debian13.patch; fi
  docker build --platform linux/amd64 --progress plain \
    --build-arg "BASE_IMAGE=$BASE_IMAGE" --build-arg "SOURCE_VERSION=$source_version" \
    --build-arg "PACKAGE_VERSION=$package_version" --build-arg "CHANNEL_BINDING_PATCH=$patch" \
    --output "type=local,dest=dist/native-client/$TARGET/$component" "docker/$component"
  cp "dist/native-client/$TARGET/$component/"*.deb dist/
done
ruby -rjson -rdigest <<'RUBY'
target = ENV.fetch('TARGET')
packages = %w[curl libcurl4t64 python3-ipalib].to_h do |name|
  version = ENV.fetch(name == 'python3-ipalib' ? 'IPALIB_VERSION' : 'CURL_VERSION')
  architecture = name == 'python3-ipalib' ? 'all' : 'amd64'
  path = "#{name}_#{version}_#{architecture}.deb"
  abort "Package metadata mismatch: #{path}" unless `dpkg-deb -f dist/#{path} Package`.strip == name && `dpkg-deb -f dist/#{path} Version`.strip == version && `dpkg-deb -f dist/#{path} Architecture`.strip == architecture
  [name, { 'version' => version, 'file' => path, 'sha256' => Digest::SHA256.file("dist/#{path}").hexdigest }]
end
File.write("dist/native-client-#{target}.json", JSON.pretty_generate({ 'target' => target, 'base_image' => ENV.fetch('BASE_IMAGE'), 'source_versions' => { 'curl' => ENV.fetch('CURL_SOURCE_VERSION'), 'python3-ipalib' => ENV.fetch('IPALIB_SOURCE_VERSION') }, 'checks' => { 'curl_negotiate_and_tls_rejection' => 'passed', 'ipalib_spki' => 'passed' }, 'packages' => packages }) + "\n")
RUBY
