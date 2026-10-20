ARG BASE_IMAGE
FROM ${BASE_IMAGE} AS build
ARG SOURCE_VERSION
ARG PACKAGE_VERSION
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends patch openssl
WORKDIR /build
RUN apt-get download python3-ipalib=${SOURCE_VERSION} \
    && dpkg-deb --raw-extract python3-ipalib_*_all.deb patched
COPY public-key-info.patch /build/
RUN cd patched \
    && patch --batch --fuzz=0 -p1 < ../public-key-info.patch \
    && sed -i "s/^Version: .*/Version: ${PACKAGE_VERSION}/" DEBIAN/control \
    && sed -i '/^Depends:/s/$/, python3-packaging/' DEBIAN/control \
    && sed -i '\|usr/lib/python3/dist-packages/ipalib/x509.py$|d' DEBIAN/md5sums \
    && md5sum usr/lib/python3/dist-packages/ipalib/x509.py >> DEBIAN/md5sums \
    && mkdir /artifacts \
    && dpkg-deb --build --root-owner-group . /artifacts/python3-ipalib_${PACKAGE_VERSION}_all.deb \
    && cd /artifacts && sha256sum ./*.deb > SHA256SUMS
COPY check.py /check.py
RUN apt-get install -y /artifacts/python3-ipalib_*.deb && python3 /check.py
FROM scratch
COPY --from=build /artifacts/ /
