ARG BASE_IMAGE
FROM ${BASE_IMAGE} AS build
ARG SOURCE_VERSION
ARG PACKAGE_VERSION
ARG CHANNEL_BINDING_PATCH=openssl-channel-binding.patch
ENV DEBIAN_FRONTEND=noninteractive
RUN sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/*.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends dpkg-dev devscripts patch python3 openssl \
    && apt-get build-dep -y curl=${SOURCE_VERSION}
WORKDIR /build
RUN apt-get source curl=${SOURCE_VERSION} && mv curl-*/ source
COPY ${CHANNEL_BINDING_PATCH} /tmp/channel-binding.patch
WORKDIR /build/source
RUN patch --batch --fuzz=0 -p1 < /tmp/channel-binding.patch \
    && DEBFULLNAME='Homelab packages' DEBEMAIL='root@home.arpa' \
       dch --newversion "${PACKAGE_VERSION}" 'Backport curl b0f6e9a: support digestless ML-DSA channel bindings.' \
    && DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage -b -us -uc -j4 \
    && mkdir /artifacts \
    && cp /build/curl_${PACKAGE_VERSION}_amd64.deb \
          /build/libcurl4t64_${PACKAGE_VERSION}_amd64.deb \
          /build/curl_${PACKAGE_VERSION}_amd64.buildinfo /artifacts/ \
    && cd /artifacts && sha256sum ./*.deb > SHA256SUMS
COPY check.py /check.py
RUN apt-get install -y /artifacts/libcurl4t64_*.deb /artifacts/curl_*.deb \
    && python3 /check.py
FROM scratch
COPY --from=build /artifacts/ /
