# Native FreeIPA client ML-DSA prerequisites

The native FreeIPA client needs two compatibility fixes before Puppet installs
and enrolls it against the CA-less ML-DSA FreeIPA server:

- curl/libcurl: upstream curl commit
  [b0f6e9a3d7be02e8f2e323aa97f2ff9b30662b32](https://github.com/curl/curl/commit/b0f6e9a3d7be02e8f2e323aa97f2ff9b30662b32)
  (unmodified for Ubuntu, adapted to the older Debian API and OpenSSL guards)
  omits the undefined `tls-server-end-point` channel binding for digestless
  signatures. Classical bindings, TLS chain/hostname checks and Kerberos server
  authentication remain enabled.
- python3-ipalib: return the existing DER SubjectPublicKeyInfo field directly,
  avoiding cryptography's unsupported ML-DSA public-key decoder. The DER bytes
  and certificate validation remain unchanged. Declare python3-packaging so
  importing the library also works on a minimal installation.

Both fixes are required on Ubuntu 26.04 and Debian 13. Debian's
`curl/libcurl4t64 8.14.1-2+deb13u7` reproduces curl error 91 (`UNDEF` digest);
`python3-ipalib 4.12.4-1` with cryptography 43.0.0 reproduces `Unknown key type`
for ML-DSA. Debian's ipa-join links the OpenSSL-backed libcurl4t64, so the curl
patch applies to the actual enrollment path.

| Target | curl and libcurl4t64 | python3-ipalib |
| --- | --- | --- |
| Ubuntu 26.04 | 8.18.0-1ubuntu2.8+homelab.1+ubuntu26.04 | 4.13.1-1+homelab.1+ubuntu26.04 |
| Debian 13 | 8.14.1-2+deb13u7+homelab.1+debian13 | 4.12.4-1+homelab.1+debian13 |

Build and test packages from authenticated distribution archives:

```sh
TARGET=ubuntu26.04 scripts/build-native-client.sh
TARGET=debian13 scripts/build-native-client.sh
```

The pinned target images come from `scripts/target.sh`. Curl is built with its
native distribution source/configuration; ipalib repackages the native signed
binary. Docker builds run installed ML-DSA/RSA/ECDSA Negotiate and negative TLS
checks, and compare all three ipalib SPKI outputs with independent OpenSSL DER.
Fresh signed-APT tests also reject missing signing keys, select the matching
target from the mixed archive and install/run both checks before publication.
The source patches/checks moved here from puppet-control-repo's Atlas bootstrap.

The **Native FreeIPA client prerequisites** workflow builds both targets and
publishes a companion signed flat APT archive using the existing OpenVox archive
key. Its versioned `native-client-RUN-ATTEMPT` release contains six packages,
per-target APT preferences and `native-client-manifest.json` with source/image
versions, checks and artifact SHA-256 checksums. It never changes the latest
release or rebuilds OpenVox/server images. Use the exact accepted release URL
configured in puppet-control-repo's shared OpenVox provisioning step.

Install `apt/native-client-TARGET.pref` with the companion source. Matching
versions have normal priority 500; foreign homelab versions are rejected. Native
distribution security updates remain eligible. There are no package holds and
no forced downgrades; a newer installed distribution revision requires review.
Refresh the source versions and recipe revision when needed, or retire the
backports once the distribution includes these fixes. Ubuntu 24.04 is outside
this native-client backport matrix.
