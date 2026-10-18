Coordinated ML-DSA OpenVox build for Ubuntu 26.04 amd64.

A published candidate becomes latest only after anonymous signed APT installation
and package-installed RSA/ML-DSA/Vault lifecycle tests pass. Use the latest
channel for promoted builds. The build manifest records source SHAs and inputs.

Package rollback requires the matching server/agent pair. It does not roll back
CA, Vault or enrolled identities. These packages do not configure PKI cutover.
