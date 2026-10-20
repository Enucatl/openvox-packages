# ML-DSA OpenVox packages

Native FreeIPA client ML-DSA compatibility packages for Ubuntu 26.04 and Debian 13
are built and published separately; see [native client prerequisites](docs/native-client.md).

Coordinated fork packages targeting Ubuntu 26.04, Ubuntu 24.04 and Debian 13 amd64.
Release `resolute-18001` passed the complete coordinated pipeline: shared source
suites, native builds and signed APT/installed RSA/ML-DSA/Vault acceptance on
all three targets, automatic promotion and the final GHCR image stage.
[Successful run](https://github.com/Enucatl/openvox-packages/actions/runs/39154755798)
tested coordinator `4f719cb678cc06a6f8c57a2e4a6a6915b84413c9`; its
[package manifest](https://github.com/Enucatl/openvox-packages/releases/download/resolute-18001/build-manifest.json)
records the resolved fork revisions and per-target inputs/results.
The public image tags `9.1.0-mldsa.18001`, `9.1.0` and `latest` all resolve to
`sha256:cbba872ef4b71865a8f7aacf395e4ff4ec28865995c5a9cec8023afe9d15b185`.
The [image manifest](https://github.com/Enucatl/openvox-packages/releases/download/resolute-18001/server-image.json)
records their provenance. Image checks passed with default RSA and explicitly
generated ML-DSA identities, verified HTTPS, shutdown and identity reuse.
Fleet rollout and PKI migration remain separate operator work.

OpenVox 9 Server is planned as a custom Ubuntu 26.04 container in
`puppet-control-repo`'s `infra` Compose stack, first on existing
`docker.home.arpa`, then on Atlas. Its image will install this repository's
signed, promoted, exact server/agent package pair and explicitly configure
Java 25, BCJSSE and the security settings below. Stock upstream image
compatibility with these custom forks is unverified. See the
[container readiness plan](https://github.com/Enucatl/puppet-control-repo/issues/12).
This is a deployment decision, not a completed container rollout; the APT
pipeline remains the native-agent delivery path and image package source.
After package acceptance, build and accept our fork server image, publish it
to `ghcr.io/enucatl/openvox-server`, and deploy it by digest through `infra`.
The image recipe, publication workflow and hosted delivery are verified below.
Infra Compose integration and live acceptance remain separate work.

A push to `feature/mldsa44` in Enucatl/openvox, Enucatl/jvm-ssl-utils,
Enucatl/openvox-server, Enucatl/openvoxserver-ca or Enucatl/vault dispatches
`packages.yml` here. Coordinator main pushes and manual dispatch also rebuild.
Each run resolves the five heads once. Shared source suites and server compilation
run once, alongside three parallel native-agent builds. The server's compressed
payload is reused byte-for-byte; only package versions and exact agent dependencies
change for each OS. The publisher signs one flat APT archive and publishes a
candidate without changing latest. Anonymous APT and installed-package lifecycle
acceptance run in parallel on all three OSes; promotion requires every target to
pass. Newer runs cancel superseded builds. Package/source failures prevent APT
promotion; image aliases move after image tests. GitHub can coalesce pending
runs, so rapid pushes rebuild the current coordinated heads.

## Credentials

- This repository's `GITHUB_TOKEN`: `contents: write` in release publishers;
  the server-image publisher also uses `packages: write` for GHCR.
- `APT_SIGNING_KEY` and `APT_SIGNING_PASSPHRASE`: dedicated encrypted signing
  subkey and its passphrase. No primary private key in Actions.
- `APT_PRIMARY_FINGERPRINT` variable:
  `775661C709ACE6F7C1CF0FF6C4B7528F03E0BB94`.
- Each source fork needs `PACKAGES_DISPATCH_TOKEN`: a fine-grained PAT restricted
  to **this repository**, with **Actions: write**. It cannot sign or publish
  packages. Set it using `gh secret set PACKAGES_DISPATCH_TOKEN --repo Enucatl/REPO`
  and enter the token at the hidden prompt. Never paste it into an issue or chat.

The generating machine holds a private primary-key/revocation backup outside
this repository. Moving that backup to offline storage is an operator task;
the pipeline does not need it. No private key belongs in Git or release assets.

## Versions and compatibility

Source version files stay aligned with upstream. A package uses
`<latest-incorporated-upstream-release>+homelab.<build>-1+<target>`, where target is
`ubuntu26.04`, `ubuntu24.04` or `debian13`.
`build` is `GITHUB_RUN_NUMBER * 1000 + GITHUB_RUN_ATTEMPT` (attempt < 1000).
Keep this workflow's counter history; promotion rejects versions that do not
exceed latest, including an old run repeated after a newer promotion. The
manifest records base tags, source SHAs, commit counts and per-target runtime
checks/checksums under `targets`. The original top-level version/runtime fields
continue to describe Ubuntu 26.04 for existing consumers. Commits alone do not
version runtime-only rebuilds. Disable conflicting upstream package sources.

The server depends on the exact tested agent version. Both rebuild together.
Rollback on a server must name both matching package versions and explicitly
allow downgrades. Agent-only hosts do not need the server.

## Server image

`docker/server/Dockerfile` installs the exact accepted server/agent pair from
the versioned signed APT archive into Ubuntu 26.04 amd64, with Java 25 and
explicit BCJSSE settings. The package manifest is included at
`/usr/share/openvox/build-manifest.json`. The Python autosigner/ENC environment
uses the locked dependencies in `docker/server/uv.lock` at the helpers' existing
`/opt/puppetlabs/puppet/venv/bin/python` path.

Build and test an accepted release locally with GitHub CLI and Docker:

```sh
bash scripts/server-image.sh resolute-18001
```

The `Server image` reusable workflow is the final stage of `Coordinated packages`,
after package acceptance and promotion, and also runs manually for a selected
accepted release. It builds/tests the image, then publishes these tags:

- `ghcr.io/enucatl/openvox-server:9.1.0-mldsa.18001` identifies upstream version and coordinated build.
- `ghcr.io/enucatl/openvox-server:9.1.0` moves with promoted builds of that upstream version.
- `ghcr.io/enucatl/openvox-server:latest` moves with the promoted package release.

These examples use the accepted `resolute-18001` APT release; the OS codename
remains an archive identifier and does not appear in image tags. Rebuilding an
older release leaves both moving aliases unchanged. Publication rejects
draft, prerelease and unaccepted package releases. The release's
`server-image.json` asset records the registry digest, image-build revision and
complete contained package manifest. Deploy by that digest. Image acceptance
and publication follow package promotion; image failures leave the accepted APT
release intact, fail the coordinated run, and can be retried through this workflow.

The image runs the packaged foreground launcher as `puppet`, with `tini` handling
signals and server logs on stdout. It neither imports nor creates CA identities
at build/startup. Prepare or restore state explicitly before normal startup.
Persist CA and server SSL directories plus writable runtime state and
code/deployment state. Supply versioned configuration explicitly and writable
runtime/log directories when applying a read-only filesystem. Do not mount over
the entire `/opt/puppetlabs/server/data/puppetserver` tree: it contains image-owned
provider policy and vendored gems that must advance with image updates. Likewise,
keep packaged service definitions from the image when supplying configuration.
State bind mounts need correct ownership.
OpenVox serves TLS/client-certificate authentication on TCP 8140.

The image's persistent state paths are `/etc/puppetlabs/puppet/ssl`,
`/etc/puppetlabs/puppetserver/ca`,
`/opt/puppetlabs/server/data/puppetserver/server_data` (the container's vardir),
and `/opt/puppetlabs/server/data/puppetserver/jruby-gems` for operator-installed
gems. Normal startup rejects missing CA/server keys and certificates. Explicit
`puppetserver ca setup` creates an RSA hierarchy by default; pass
`--key-type mldsa44` to create ML-DSA-44 root, intermediate and server identities.
Setup or the rehearsed external-CA import remains an operator action, using the
same mounts and `/etc/puppetlabs/puppet/puppet.conf`. Image acceptance starts and
recreates servers with both default RSA and explicit ML-DSA setups.

The [first hosted image publication](https://github.com/Enucatl/openvox-packages/actions/runs/39153344363)
passed image build/lifecycle checks and published `9.1.0-mldsa.13001`, `9.1.0`
and `latest`. Anonymous registry requests verified all three at digest
`sha256:38a0923732977a0eae63305d2c53cb91b18321bf26142814ab916ff0524d300b`.
Its [image manifest](https://github.com/Enucatl/openvox-packages/releases/download/resolute-13001/server-image.json)
records the historical package/build provenance. The full multi-target pipeline
has now passed as recorded above; live infrastructure rollout remains separate.

`tests/server-image.sh IMAGE` checks nonroot runtime/helper imports, explicit
test-only RSA and ML-DSA CA setup, verified HTTPS, foreground logging, graceful shutdown
and identity-preserving container recreation. It uses disposable volumes and
does not contact production services. Full control-repo ML-DSA enrollment and
Atlas recovery remain the open gates in issue #12/#18. Verify GHCR visibility
and pull access before rollout; retain registry access and image recovery inputs
independently if the package is private.

## Recovering a failed run

After a publication or acceptance failure, fix the cause and rebuild the complete
package pair: choose **Re-run all jobs** in Actions, or start a new `packages.yml`
workflow run on `main`. Rerunning all jobs regenerates the packages and manifest
with the new attempt number; a new workflow run uses a new run number. If the fix
changes the coordinator, start a new workflow run to use the updated revision;
reruns use the original coordinator revision.

Do not choose **Re-run failed jobs** or retry only the publisher. When the build
jobs already succeeded, that path downloads their original target artifacts and
restores the original build number from the manifest, despite the increased
workflow attempt number. It can therefore collide with the existing candidate
tag. For example, acceptance may fail after the candidate has been published;
leave that candidate and its assets intact and rebuild under a new build number.
Do not delete or overwrite published candidate assets to make a retry succeed.
The candidate stays out of latest until acceptance passes and promotion succeeds.

An older run can still fail the version-ordering guard after a newer run has
been promoted, even when all jobs are rerun. Start a new workflow run in that
case; increasing the attempt alone cannot advance an older run past a newer one.

## Installation

After validating the full fingerprint through your trusted operator path,
install `openvox-archive-keyring.asc` under `/etc/apt/keyrings/` with mode 0644.
Create `/etc/apt/sources.list.d/openvox-homelab.sources`:

```text
Types: deb
URIs: https://github.com/Enucatl/openvox-packages/releases/latest/download/
Suites: ./
Architectures: amd64
Signed-By: /etc/apt/keyrings/openvox-archive-keyring.asc
```

Before the first update, install the matching preferences file from this repository:

| Host OS | Preferences file |
| --- | --- |
| Ubuntu 26.04 | `apt/ubuntu26.04.pref` |
| Ubuntu 24.04 | `apt/ubuntu24.04.pref` |
| Debian 13 / Proxmox VE 9 | `apt/debian13.pref` |

For example, on a Proxmox host:

```sh
sudo install -m 0644 apt/debian13.pref /etc/apt/preferences.d/openvox-homelab
sudo apt update
apt-cache policy openvox-agent openvox-server
sudo apt install openvox-agent
```

The shared index contains all three OS variants. These preferences allow matching
versions and reject other variants; APT does not interpret the version suffix as
an OS restriction. Install the appropriate file on every client, including 26.04,
and replace it when upgrading the host OS. Releases also carry these `.pref` files.
The first multi-target release has a retained rollback pair only for 26.04;
subsequent releases retain the previous matching pair for every target.

For the production server, install the exact accepted `openvox-server` and
`openvox-agent` pair during the custom Ubuntu 26.04 image build in
this repository, recording its versioned release and manifest. Deploy through
`puppet-control-repo` and run that
container on the existing Docker host only after container acceptance; its
26.04 userland does not require first upgrading the host OS. Rebuild and accept
the image to update the server pair. Host-agent APT upgrades do not update it.
This does not schedule fleet installation or migrate existing PKI identities.

### Standalone package verification reference

The following host-systemd procedure remains useful for package verification.
It is not the target production server deployment procedure. For a standalone
Ubuntu 26.04 verification host, install `openvox-server` with its exact matching
agent; subsequent `sudo apt update && sudo apt upgrade` advances the tested pair.

For ML-DSA install `openjdk-25-jre-headless`, then set the supported service
settings in `/etc/default/puppetserver`, preserving the existing heap options:

```sh
JAVA_BIN="/usr/lib/jvm/java-25-openjdk-amd64/bin/java"
JAVA_ARGS="-Xms2g -Xmx2g -Djava.security.properties=/opt/puppetlabs/server/data/puppetserver/java.security.mldsa -Djdk.tls.client.SignatureSchemes=mldsa44,rsa_pss_rsae_sha256,rsa_pss_pss_sha256,ecdsa_secp256r1_sha256,ed25519,rsa_pkcs1_sha256 -Djdk.tls.server.SignatureSchemes=mldsa44,rsa_pss_rsae_sha256,rsa_pss_pss_sha256,ecdsa_secp256r1_sha256,ed25519,rsa_pkcs1_sha256 -Dorg.bouncycastle.jsse.client.SignatureSchemesCert=mldsa44,rsa_pss_rsae_sha256,rsa_pss_pss_sha256,ecdsa_secp256r1_sha256,ed25519,rsa_pkcs1_sha256 -Dorg.bouncycastle.jsse.server.SignatureSchemesCert=mldsa44,rsa_pss_rsae_sha256,rsa_pss_pss_sha256,ecdsa_secp256r1_sha256,ed25519,rsa_pkcs1_sha256"
```

Restart with `sudo systemctl restart puppetserver`. The security-file property
uses one equals sign to append to the runtime security configuration. The
installed provider file is opt-in; PKI migration remains separate operator work.
Use literal values: systemd reads this file without shell-variable expansion.
The container launcher must explicitly apply the same Java/provider/security
settings; a foreground container process does not inherit systemd environment
files automatically. Container launcher and lifecycle acceptance remain part of
the control-repository migration plan.

`latest` requests are independent: a promotion can cause an index hash mismatch.
APT must reject it; repeat `apt update`. Previous package assets remain available
in the next release, and complete versioned releases remain for rollback.
Never use `Trusted: yes` or disable signature/hash checks.

## Checks

`tests/archive.sh` exercises archive integrity. `tests/server-recipe.rb` invokes
`scripts/configure-build.rb` to check coordinated versions, local SSL coordinates
and invalid inputs, and tests the local CA gem installer. `tests/source-recipe.rb`
checks that the Vault bundle resolves the local OpenVox fork. `tests/bundler-env.rb`
runs the same `scripts/server-specs.rb` entry point as the source tests and rejects
the original MRI Bundler environment leak into Rake's child processes.
`tests/build-manifest.rb` runs the workflow's recording step against fixtures to
verify identity, check records, runtime inputs, checksums and missing evidence.
`tests/targets.sh` checks target selection and agent-build inputs;
`tests/source-snapshot.rb` verifies that every job uses the same resolved commits.
`tests/repackage-server.rb` verifies unchanged compressed payload/ownership and
matching package metadata. `tests/release-manifest.rb` checks target provenance
and checksums, and `tests/publication.rb` checks previous-pair retention and
candidate publication guards. Archive tests also exercise all three OS preferences.
`tests/acceptance-diagnostics.rb` verifies the failure-stage output and diagnostic
allowlist, including failures before lifecycle startup. Run the shell/Ruby checks
and these focused tests before the full workflow; `scripts/source-tests.sh`
mutates its disposable source checkouts and must not run against working trees.
Source tests and installed-agent ML-DSA checks precede candidate
publication. Package acceptance exercises anonymous APT, missing-key rejection,
paired upgrade/rollback when a previous release exists, and installed-package
RSA/ML-DSA enrollment, catalogs, renewal, revocation and Vault integration.
It retains external-CA import coverage and separately creates fresh hierarchies
using `ca setup` without a flag (RSA) and with `--key-type mldsa44`.
The lifecycle uses the installed authorization file and foreground launcher with
explicit Java/provider settings. A checksum-verified official Ubuntu 26.04 KVM
guest also passed packaged systemd startup with default RSA/SunJSSE and explicit
Java 25/BCJSSE/PKIX configuration, including verified HTTPS and actual process
settings. The VM provider restart reused its RSA identity; the complete ML-DSA
identity lifecycle ran in installed-package acceptance.
The fixture cleanup removes the overwritten synthetic ML-DSA hierarchy and
synthetic fixture-only issuance/revocation. The package lifecycle still checks
actual enrollment, issuer signatures, key usage, TLS 1.3 groups and both TLS
signatures, renewal, CRL refresh/reload, unauthorized access, revocation and
replacement identities, plus Vault authentication/issuance and negative controls.
ML-DSA lifecycles require the real agent to negotiate `X25519MLKEM768` and
`mldsa44` authentication in both directions. The external ML-DSA lifecycle uses
Vault's generated hierarchy directly. Completion is recorded for
each lifecycle; an arbitrary assertion-count threshold is not a coverage gate.
The disposable distribution test verified the exact coordinator tag target,
complete native candidate publication, unchanged latest after an induced
acceptance failure, signed anonymous APT and paired rollback/upgrade, then explicit
promotion. It preserved existing releases and restored the original disposable
latest designation afterward. Persistent evidence:
[complete-flow checks](https://github.com/Enucatl/openvox-packages-acceptance/releases/download/resolute-13001/task12-verification.txt),
[Ubuntu 26.04 systemd checks](https://github.com/Enucatl/openvox-packages-acceptance/releases/download/resolute-13001/ubuntu26-systemd-resolute-13001.txt).
Acceptance evidence includes disposable private identities; it is never uploaded
as public release assets. Ubuntu 24.04 and Debian 13 are now pipeline targets;
their first hosted candidate must pass the same acceptance before promotion.
Local extension verification built both new native agents and passed 44 installed
crypto checks per target. Each also passed the full 88-check RSA/ML-DSA/Vault
lifecycle against a signed local archive containing all three OS variants, using
the `resolute-13001` server payload with target-specific control metadata. These
checks verified native upstream-to-fork installation, matching OS selection and
missing-key rejection. Public HTTPS candidate publication and the complete shared
source suites remain the hosted workflow's gates; no fleet hosts were changed.

Vault source tests run early with `tests/Gemfile.vault` against the local
OpenVox fork. Its official helper 8.0.0 uses a workspace-only dependency override
for current syntax tooling, alongside facts helper 6.3. Remove that override when
the upstream helper supports the OpenVox syntax dependency directly.
