#!/bin/sh
set -eu
mkdir -p RSA
cd RSA
for identity in root sub server; do
  openssl genpkey -algorithm RSA -out "$identity.key" 2>/dev/null
done
openssl req -new -x509 -key root.key -out root.pem -subj /CN=TestRoot -days 2 -addext 'basicConstraints=critical,CA:TRUE,pathlen:1' -addext 'keyUsage=critical,keyCertSign,cRLSign'
cat > sub.ext <<'EXTENSIONS'
basicConstraints=critical,CA:TRUE,pathlen:0
keyUsage=critical,keyCertSign,cRLSign
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EXTENSIONS
openssl req -new -key sub.key -out sub.csr -subj /CN=TestSub
openssl x509 -req -in sub.csr -CA root.pem -CAkey root.key -set_serial 2 -out sub.pem -days 2 -extfile sub.ext
openssl verify -CAfile root.pem sub.pem
