#!/bin/sh
set -eu
cd RSA
for ca in root sub; do
  mkdir -p "$ca-db/newcerts"
  : > "$ca-db/index"
  printf '1000\n' > "$ca-db/crlnumber"
  cat > "$ca.cnf" <<CONFIG
[ca]
default_ca=issuer
[issuer]
database=$ca-db/index
new_certs_dir=$ca-db/newcerts
certificate=$ca.pem
private_key=$ca.key
crlnumber=$ca-db/crlnumber
default_md=default
default_crl_days=1
policy=policy
crl_extensions=crl_ext
[policy]
commonName=supplied
[crl_ext]
authorityKeyIdentifier=keyid:always
CONFIG
  openssl ca -config "$ca.cnf" -gencrl -out "$ca.crl" -batch
done
