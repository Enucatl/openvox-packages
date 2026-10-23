Coordinated ML-DSA OpenVox build for Ubuntu 26.04 and Debian 13 amd64.

A published candidate becomes latest only after anonymous signed APT installation
and installed-package lifecycle tests pass on both targets. Use the latest
channel for promoted builds. The build manifest records source SHAs and inputs.

Package rollback requires the matching server/agent pair. It does not roll back
CA, Vault or enrolled identities. These packages do not configure PKI cutover.

Install the OS-specific APT preferences file before using the shared flat archive;
it excludes packages for the other operating systems. See the README for setup.
