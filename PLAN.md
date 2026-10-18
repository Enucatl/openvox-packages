# Publishing the ML-DSA OpenVox packages

Status: simplified implementation verified, 18 October 2026. Release `resolute-13001`
passed the complete automated pipeline: builds, source suites, signed public APT
installation, retained-pair rollback/upgrade, incompatible agent-only downgrade
rejection and both installed RSA/ML-DSA/Vault lifecycles. It was automatically
promoted to latest and retains the tested `resolute-11001` package pair.
[Successful full run](https://github.com/Enucatl/openvox-packages/actions/runs/39141160033)
tested coordinator `caea3dde7605511102221d01612bc9b07b6b5742`; the release manifest
records the exact five fork revisions, package hashes and runtime inputs.

The final suites passed: Vault 253 examples; agent 25,368 examples with 22 existing
pending; SSL 30 tests/291 assertions plus `IssuerSigningTest`; CA 283 examples;
server Clojure 224 tests/12,824 assertions and 223 tests/12,813 assertions; server
Ruby 78 examples. The earlier run failed a nested logging-capture assertion;
the final server revision retains all assertions with capture established by the
existing fixture before server startup.

The disposable distribution test used unchanged publication/acceptance entry
points and a fresh disposable signer. It verified the exact target SHA, complete
candidate assets, unchanged latest after forced acceptance failure, anonymous
signed APT, exact pairing, rollback/upgrade, incompatible downgrade rejection and
explicit promotion. Historical releases were preserved and the original
disposable latest restored. A real KVM Ubuntu 26.04 guest independently passed
packaged systemd startup with default RSA/SunJSSE and explicit Java 25/BCJSSE/PKIX;
its provider restart reused RSA identity, while installed-package acceptance
verified the full ML-DSA identity lifecycle.
[Complete-flow evidence](https://github.com/Enucatl/openvox-packages-acceptance/releases/download/resolute-13001/task12-verification.txt),
[VM evidence](https://github.com/Enucatl/openvox-packages-acceptance/releases/download/resolute-13001/ubuntu26-systemd-resolute-13001.txt).

## Publishing decision

Use the public distribution repository
`Enucatl/openvox-packages`. Publish one coordinated GitHub Release per successful
build. Each release contains a complete, signed, flat APT repository for
**Ubuntu 26.04 (resolute), initially amd64**. Include architecture-independent
packages as produced by the build tools. Do not publish RPMs or other Ubuntu
series in this first implementation.

Clients use this stable repository address:

```text
https://github.com/Enucatl/openvox-packages/releases/latest/download/
```

GitHub redirects each asset request to the release designated as latest.
`apt update` reads its package index; `apt upgrade` selects newer package
versions. No Pages deployment, PPA, GHCR registry or intranet APT server is needed
for this proposed layout. GitHub supplies file hosting and redirects; our
workflow must generate the repository metadata and signatures.

The repository exists; the APT URLs become usable only after a tested release.
[GitHub documents the stable latest-asset URL here.](https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases)

## Source and build organization

Keep source changes in the five existing forks. Follow `feature/mldsa44` in
each; do not freeze deployment configuration at the first reviewed commits.

| Fork | Distribution role |
| --- | --- |
| `Enucatl/openvox` | Build the `openvox-agent` Debian package. |
| `Enucatl/jvm-ssl-utils` | Build the SSL library consumed by the server. |
| `Enucatl/openvox-server` | Build the `openvox-server` Debian package. |
| `Enucatl/openvoxserver-ca` | Build the patched CA gem and include it in the server package. |
| `Enucatl/vault` | Deploy the module through its Puppetfile branch; record the revision tested with the packages. |

Use `openvox-packages` for build coordination, release assets, the public archive
key and installation instructions. A push to `feature/mldsa44` in any of the five
forks must dispatch a coordinated build through `packages.yml` in the distribution
repository. Manual dispatch and coordinator main pushes can also rebuild.
Tests, candidate publication, anonymous APT acceptance and promotion to latest
are automatic; no per-release approval is required.

Each fork stores `PACKAGES_DISPATCH_TOKEN`, a fine-grained PAT restricted to the
distribution repository with Actions: write. Its own `GITHUB_TOKEN` cannot
dispatch workflows across repositories. The distribution repository uses its
own `GITHUB_TOKEN` with contents: write for publication; it alone holds the
archive signing secrets. No signing material goes into source forks.

At the start of each build, resolve all five branch heads once and use those
checkouts throughout the job. Record their SHAs, runtime versions, test results
and artifact checksums in a build manifest. These identify what was built;
they do not prevent the next build from consuming newer branch heads.

Build dependencies and packages in this order:

1. Build/install the forked SSL library into the job's local Leiningen/Maven
   repository. The server must use this build, not an unrelated remote snapshot.
   A public upstream SSL-library release is not required.
2. Build the patched CA CLI gem with an explicit output filename. The checked-in
   server installer consumes the coordinated local gem; ordinary upstream builds
   retain the public `openvoxserver-ca 3.3.0` fallback.
3. Build the agent using Vanagon under `openvox/packaging`. Reuse upstream
   runtime tarballs where they supply the required Ruby/OpenSSL combination.
4. Build the server with EZbake and the matching SSL library and CA gem. Include
   BC TLS and install the opt-in Java security configuration at a documented
   package path. Configure the tested Java 25 runtime explicitly for ML-DSA.
5. Install the actual packages on disposable Ubuntu 26.04 systems and exercise
   the OpenVox/Vault paths before publishing them as the default release.

Keep existing package names and supported filesystem/service layouts.
Permanent Ubuntu 26.04, Debian revision, Java 25 builder, security-file installation
and local CA-gem support live in the source-fork recipes. The coordinator's
`scripts/configure-build.rb` applies only generated build versions, exact agent
pairing and unique local SSL Maven coordinates, for both package and source tests.
EZbake uses disposable clean Git clones. Vault tests use the checked-in four-entry
`tests/Gemfile.vault`; server Ruby tests use `scripts/server-specs.rb` to isolate
Bundler's child environment.

### Package versions and compatibility

Keep the forks' source version files aligned with upstream. Generate the Debian
package version in the build workspace; do not commit a version bump to every
fork for each distribution build. Use:

```text
<upstream-release-version>+homelab.<build-number>-1+ubuntu26.04
# Example: 9.1.0+homelab.42-1+ubuntu26.04
```

The base is each component's latest incorporated upstream release tag, recorded
in the manifest, not an unreleased next-version value such as `9.1.1-SNAPSHOT`.
Fetch upstream release tags and sufficient history to identify that base. Agent
and server bases may differ. Preserve any upstream Debian epoch if one exists.
Pass generated versions through the packaging tools' overrides and inspect the
actual `.deb` Version fields; do not assume their default Git version conversion
produces this format. Maven and gem dependency coordinates remain separate from
the Debian package version.

Allocate a persistent, increasing build number in the coordinating repository
for every new build attempt, including reruns. Use the same number for the
coordinated package set. A rebuild of unchanged source with a new runtime,
vendored gem, SSL library or packaging recipe must also get a new number.
Record commit count since the base tag and the exact SHA in the manifest for
traceability; commit count alone is not a package version counter because
rebases can reduce it and dependency-only rebuilds do not change it.
The implementation uses `GITHUB_RUN_NUMBER * 1000 + GITHUB_RUN_ATTEMPT`, requiring
attempt < 1000. Preserve the workflow's counter history; a rerun older than the
current promoted version must fail the ordering check. GitHub may coalesce
pending runs; each run resolves the current coordinated branch heads.

APT compares version fields, not release dates or commit ancestry. At equal
repository priority, the intended ordering is:

```text
9.1.0-1+ubuntu26.04
  < 9.1.0+homelab.42-1+ubuntu26.04
  < 9.1.0+homelab.43-1+ubuntu26.04
  < 9.1.1-1+ubuntu26.04
```

The `+homelab` suffix sorts after the same upstream release; it is not ignored
as build metadata. A newer upstream release still sorts above the fork's older
base. Therefore disabling conflicting upstream sources remains required. Do not
use an artificial epoch to keep the fork permanently above upstream.
[Debian version ordering](https://www.debian.org/doc/debian-policy/ch-controlfields.html#version).

Before promotion, use `dpkg --compare-versions` to require each generated package
version to exceed its last promoted version, and check the ordering examples
above. Reject a regressing base/version rather than publishing an invisible
update. Never overwrite different contents under the same version or filename.

For this first pipeline, generate the server's Debian dependency as
`openvox-agent (= <full-agent-package-version-tested-with-this-server>)`.
The server loads its Ruby code from the installed agent; the upstream
`openvox-agent (>= 9.1.0)` dependency also accepts unpatched upstream code.
An exact dependency makes the tested pair explicit without claiming that every
newer agent is compatible. Rebuild and publish both packages together, even when
only one fork changes. Normal APT upgrades can then advance the installed pair
together, without version holds. Server hosts must roll back both packages to
the matching retained pair; agent-only hosts can update independently. Widen
this dependency to a supported version range only after testing mixed versions.

The existing agent workflow can return artifacts without uploading to upstream
S3. Adapt the server publisher, which assumes upstream credentials, and the CA
gem release workflow, which skips forks. Use our own publishing permissions.

## What each GitHub Release contains

Use a unique build tag such as `resolute-20261018.1`. All assets live directly
under that release's download URL, without `pool/` or `dists/` directories:

```text
openvox-agent_<version>_amd64.deb
openvox-server_<version>_<architecture>.deb
Packages
Packages.gz
Release
InRelease
Release.gpg
build-manifest.json
SHA256SUMS
```

Use the architecture actually reported by each package. Retain at least the
previous promoted package versions in the next release as well, using their
original versioned filenames. Keep older complete releases for rollback.

`Packages` lists package names, versions, dependencies, sizes, SHA-256 hashes
and relative filenames such as `./openvox-agent_<version>_amd64.deb`. Generate
it with `apt-ftparchive`; compress it to `Packages.gz`. Generate `Release` from
the final indexes, then sign it. Keep the repository's Origin, Label and other
identity fields stable between builds. Store build identity in the manifest.
[Index-generation reference](https://manpages.ubuntu.com/manpages/resolute/man1/apt-ftparchive.1.html).

Publish with `gh release create --latest=false --target "$GITHUB_SHA"`, passing
the explicit archive asset list. GitHub CLI stages asset-bearing releases as a
draft, uploads all files, then publishes. Run anonymous APT download, signature,
installation and upgrade checks against that release's versioned URL; draft
assets cannot exercise the public client download path. Only after those checks
pass, append `Acceptance: passed` to the notes and explicitly promote with
`gh release edit --latest --notes-file RELEASE-NOTES.md`. Keep failed
candidates out of latest. Test latest-URL redirects and metadata mixing in a
disposable distribution repository before enabling production promotion.
[GitHub release publication controls](https://docs.github.com/en/rest/releases/releases).

Use one publisher at a time and recheck version ordering under that serialization
so a slower older build cannot promote over a newer one. A failed build must
leave the existing latest release unchanged.

GitHub's latest channel is intended here for promoted, tested package builds.
Do not rely on prereleases being selected by `releases/latest`; keep unrelated
key/documentation releases from becoming latest. Preserve old versioned
releases and do not replace their assets after promotion.

## What needs signing

APT needs an **OpenPGP archive signature**, independent of GitHub account or
commit signatures. The verification chain is:

```text
trusted archive public key
  -> verifies InRelease (the signed Release contents)
    -> authenticates the SHA-256 hash of Packages / Packages.gz
      -> authenticates the SHA-256 hash of each downloaded .deb
```

Create both forms from the same final `Release` file:

```sh
gpg --local-user "$APT_SIGNING_FINGERPRINT" --digest-algo SHA256 \
  --clearsign --output InRelease Release

gpg --local-user "$APT_SIGNING_FINGERPRINT" --digest-algo SHA256 \
  --armor --detach-sign --output Release.gpg Release
```

`InRelease` is the primary signed metadata; `Release.gpg` supports the detached
signature fallback. APT does not need a separate signature embedded in every
`.deb`. `SHA256SUMS` is useful for inspection but alone does not establish trust.
GitHub's Verified badge and a signed source tag do not replace archive signing.
[APT's signing requirements](https://manpages.ubuntu.com/manpages/resolute/man8/apt-secure.8.html).

### Is the Ed25519 key already on GitHub enough?

The algorithm name alone is insufficient; the key format and purpose matter:

| Existing key | Suitable for APT archive signing? |
| --- | --- |
| SSH Ed25519 key, including one used to sign Git commits | No. SSH signatures are not OpenPGP archive signatures. |
| OpenPGP Ed25519 key with signing capability, also registered on GitHub | Potentially yes, if we control its private signing material and explicitly distribute its public key to APT clients. |
| Public key uploaded to GitHub, with no available private signer | No. A public key can verify a signature, not create one. |

We have not inspected which type the existing key is. GitHub registration does
not automatically make APT trust it. An SSH public key starts with
`ssh-ed25519`; an ASCII-armored OpenPGP public key starts with
`-----BEGIN PGP PUBLIC KEY BLOCK-----`.
[GitHub supports distinct SSH and GPG signature mechanisms.](https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification)

Create a **new, dedicated OpenPGP archive-signing key with an Ed25519 signing
subkey** before the first package publication. Keep the primary key offline and
validate the signing subkey with Ubuntu 26.04's verifier in the first repository
test. GnuPG supports Ed25519; do not convert or reuse the existing SSH key.
Keep personal SSH/authentication keys out of the publisher.
[GnuPG key management](https://www.gnupg.org/documentation/manuals/gnupg/OpenPGP-Key-Management.html).

Created archive primary-key fingerprint:
`775661C709ACE6F7C1CF0FF6C4B7528F03E0BB94`.
The encrypted signing subkey and passphrase are configured as
`APT_SIGNING_KEY` and `APT_SIGNING_PASSPHRASE` in the distribution repository;
`APT_PRIMARY_FINGERPRINT` is a repository variable. The primary-key/revocation
backup is outside the source workspace at
`/home/user/.local/share/openvox-packages/archive-signing`. It remains local;
moving that backup to independent offline storage is still an operator task.

Export the archive public key as `openvox-archive-keyring.asc` and publish its
full fingerprint in the control repository and installation instructions.
For CI, make only the dedicated signing material available to the trusted
release job, preferably a signing subkey with the primary key kept offline.
Protect its passphrase separately; retain an independent private-key/revocation
backup. Never expose the signer to pull-request jobs or put private keys in
release assets. The publishing job also needs permission to write releases;
that GitHub token authorizes uploads and does not create an APT signature.

OpenVox's ML-DSA X.509 hierarchy is a separate trust system. Using Ed25519
OpenPGP signatures for APT does not make package distribution post-quantum.

## Client configuration

These are operator setup instructions. Authenticate the repository key and
review the acceptance evidence below before using them on the fleet.
The public repository requires no GitHub token on clients.

### 1. Install and authenticate the public archive key

Obtain the full expected OpenPGP primary-key fingerprint through the trusted
control-repo/operator path. Confirm the fingerprint below before use. Download
the public key, compare its fingerprint, then install it:

```sh
sudo apt install ca-certificates curl gnupg

EXPECTED_APT_FINGERPRINT='775661C709ACE6F7C1CF0FF6C4B7528F03E0BB94'
key_file=$(mktemp)
curl --fail --silent --show-error --location \
  https://raw.githubusercontent.com/Enucatl/openvox-packages/main/openvox-archive-keyring.asc \
  --output "$key_file"

actual_fingerprint=$(gpg --show-keys --with-colons "$key_file" \
  | awk -F: '$1 == "pub" { primary = 1; next } primary && $1 == "fpr" { print $10; primary = 0 }')
test "$actual_fingerprint" = "$EXPECTED_APT_FINGERPRINT" || {
  echo 'Archive key fingerprint mismatch; do not install this key.' >&2
  exit 1
}

sudo install -d -m 0755 /etc/apt/keyrings
sudo install -m 0644 "$key_file" /etc/apt/keyrings/openvox-archive-keyring.asc
rm "$key_file"
```

This comparison requires exactly one primary-key fingerprint, matching the
expected key; signing-subkey fingerprints do not count as extra primary keys.
Do not treat a fingerprint fetched from the same unverified download as an
independent trust check. Only the public key goes onto clients.

### 2. Add the flat repository

Create `/etc/apt/sources.list.d/openvox-homelab.sources`:

```text
Types: deb
URIs: https://github.com/Enucatl/openvox-packages/releases/latest/download/
Suites: ./
Architectures: amd64
Signed-By: /etc/apt/keyrings/openvox-archive-keyring.asc
```

There is no `Components` field for this flat layout. The keyring is readable
by APT and scoped to this source. Do not use `apt-key`, `Trusted: yes` or
unauthenticated-package overrides.
[Flat sources and Signed-By](https://manpages.ubuntu.com/manpages/resolute/man5/sources.list.5.html).

### 3. Install and update

On Ubuntu 26.04 amd64, inspect candidates before the first installation:

```sh
sudo apt update
apt-cache policy openvox-agent openvox-server

# Every managed Ubuntu node:
sudo apt install openvox-agent

# Configuration server only:
sudo apt install openvox-server
```

Keep Ubuntu's normal repositories. Review and disable conflicting old
Puppet/OpenVox sources when switching to these packages, so a higher upstream
version cannot silently replace the fork build. Confirm the candidate's origin
and version using `apt-cache policy`. Do not apply fixed-version holds.

Subsequent updates use `sudo apt update` followed by `sudo apt upgrade`, through
the agreed canary/fleet process. Publishing a release makes a new version
available; it does not itself schedule installation. Configure unattended
upgrades separately only if we decide to use them.

Installation does not turn existing RSA identities into ML-DSA identities.
Provider configuration, CA import, `key_type=mldsa44`, enrollment and the PKI
cutover remain the work described in migration issues #12/#13/#23.

Restore a specific previous tested package set using the corresponding
versioned release URL, its signed indexes and matching versions. An intentional
downgrade needs APT's explicit downgrade handling; package rollback does not
restore CA, Vault or enrolled-identity state.
[Ubuntu explains why installation by repository package name verifies the archive chain.](https://documentation.ubuntu.com/security/software-integrity/archive-verification/)

## Latest-release consistency and retention

GitHub redirects each request independently. If latest changes during a client
operation, an old index may request an old package through the new release.
Retaining previous package files covers that bounded transition window.

There is also a metadata race: `InRelease` can come from build A while
`Packages.gz` comes from build B. Retaining old `.deb` files does not solve it.
APT must reject the hash mismatch; rerun `apt update` after promotion finishes.
Uploading a complete draft prevents incomplete published releases, but does
not make separate latest-URL requests an atomic snapshot.

GitHub's latest download redirects can also briefly lag its release API after
promotion. The disposable transition test observed an older signed index until
ordinary update retries reached the new release. Candidate acceptance uses the
versioned URL; do not require an immediate latest-URL switch or bypass APT
verification to force one.
[Hosted transition evidence](https://github.com/Enucatl/openvox-packages-acceptance/releases/tag/test-1.1).

Do not advertise APT by-hash support unless the required paths actually work
through GitHub's flat asset URLs. Never weaken signature or hash verification
to hide publication races. Test the transition explicitly. If occasional safe
retries are operationally unacceptable, use a conventional repository host
with a publication strategy that supports consistent index access.

Retain older versioned releases independently of the number of previous
packages carried into the latest release. A client with very old cached
indexes may need a fresh `apt update` before downloading. Keep signed
repository metadata valid for the intended update cadence; if we set
`Valid-Until`, provide a refresh cadence before it expires.

## Implementation checklist

- [x] Create `Enucatl/openvox-packages` and its coordinated build workflow.
- [x] Create a new, dedicated OpenPGP archive-signing key with an Ed25519 signing
      subkey, publish the public key/fingerprint and configure the CI signer.
- [ ] Move the local primary-key/revocation backup to independent offline storage.
- [x] Adapt Vanagon/EZbake and the CA gem input to build only Ubuntu 26.04
      artifacts from the current fork branches, with generated package versions,
      an increasing build counter and the server's exact tested-agent dependency.
- [x] Record source/runtime provenance and build the complete flat asset set.
- [x] Sign metadata, stage and verify a complete draft, publish with
      `make_latest: false`, pass anonymous APT checks at the versioned URL, then
      promote through a serialized job. Keep previous releases/packages.
- [x] In disposable Ubuntu 26.04 clients, verify real GitHub redirects, signed
      `apt update`, installation, upgrade, retained-version download and rollback.
- [x] Verify installing the server over an upstream agent brings in the matching
      fork agent, upgrading advances both packages, and downgrading only the
      agent cannot silently leave an incompatible server installed. Test rollback
      of the complete retained pair.
- [x] Verify failures for an untrusted key, modified package, modified index,
      missing signature and metadata mixing during a latest-release switch.
- [x] Exercise package-installed OpenVox enrollment, catalogs, Vault, renewal,
      revocation and the RSA regression controls; do not substitute source overlays.
- [x] Capture client setup in the distribution/control repo documentation.
- [ ] Run the live canary before fleet expansion. Keep actual deployed versions
      as records, not source pins.

Ubuntu 26.04-only publication does not supply packages for current Ubuntu 24.04
or Debian/Proxmox nodes. The earlier all-existing-nodes-first migration sequence
needs an explicit deployment path for those systems; do not install Ubuntu
26.04 binaries on them as a substitute.

The repository, signer and automatically promoted tested releases now exist. Fleet client
configuration has not been changed; actual fleet canary/cutover remains separate.
