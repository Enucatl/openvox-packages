# ML-DSA OpenVox packages

Coordinated fork packages for Ubuntu 26.04 amd64. Release `resolute-11001` passed
the complete automated build, source-test, public signed APT, upgrade/rollback
and 87-assertion lifecycle pipeline and was automatically promoted to latest.
[Validation run](https://github.com/Enucatl/openvox-packages/actions/runs/39129563850).
Fleet rollout and PKI migration remain separate operator work.

A push to `feature/mldsa44` in Enucatl/openvox, Enucatl/jvm-ssl-utils,
Enucatl/openvox-server, Enucatl/openvoxserver-ca or Enucatl/vault dispatches
`packages.yml` here. Coordinator main pushes and manual dispatch also rebuild.
Each run resolves the five heads once, tests those sources, builds actual
Vanagon/EZbake packages, signs an APT archive, publishes a candidate without
changing latest, runs anonymous APT and installed-package lifecycle tests, then
promotes. Runs are serialized; failed runs leave latest unchanged. GitHub can
coalesce pending runs, so rapid pushes rebuild the current coordinated heads.

## Credentials

- This repository's `GITHUB_TOKEN`: `contents: write` in the publisher only.
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
`<latest-incorporated-upstream-release>+homelab.<build>-1+ubuntu26.04`.
`build` is `GITHUB_RUN_NUMBER * 1000 + GITHUB_RUN_ATTEMPT` (attempt < 1000).
Keep this workflow's counter history; promotion rejects versions that do not
exceed latest, including an old run repeated after a newer promotion. The
manifest records base tags, source SHAs and commit counts. Commits alone do not
version runtime-only rebuilds. Disable conflicting upstream package sources.

The server depends on the exact tested agent version. Both rebuild together.
Rollback on a server must name both matching package versions and explicitly
allow downgrades. Agent-only hosts do not need the server.

## Recovering a failed run

After a publication or acceptance failure, fix the cause and rebuild the complete
package pair: choose **Re-run all jobs** in Actions, or start a new `packages.yml`
workflow run on `main`. Rerunning all jobs regenerates the packages and manifest
with the new attempt number; a new workflow run uses a new run number. If the fix
changes the coordinator, start a new workflow run to use the updated revision;
reruns use the original coordinator revision.

Do not choose **Re-run failed jobs** or retry only the publisher. When the build
job already succeeded, that path downloads its original `packages` artifact and
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

Run `sudo apt update`, inspect `apt-cache policy openvox-agent openvox-server`,
then install `openvox-agent` on nodes and `openvox-server` on the server.
Subsequent `sudo apt update && sudo apt upgrade` advances tested package pairs.
This does not schedule fleet installation or migrate existing PKI identities.

For ML-DSA explicitly configure Java 25 and the installed opt-in
`/opt/puppetlabs/server/data/puppetserver/java.security.mldsa` provider file.
Keep the RSA/default provider behavior unless doing the separate PKI migration.

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
Source tests and installed-agent ML-DSA checks precede candidate
publication. Package acceptance exercises anonymous APT, missing-key rejection,
paired upgrade/rollback when a previous release exists, and installed-package
RSA/ML-DSA enrollment, catalogs, renewal, revocation and Vault integration.
The lifecycle uses the installed authorization file and foreground launcher with
explicit Java/provider settings. Packaged systemd startup remains unverified
until the disposable Ubuntu 26.04 VM check.
Acceptance evidence includes disposable private identities; it is never uploaded
as public release assets. Ubuntu 24.04 and Debian/Proxmox are outside this build.

Vault source tests run early with `tests/Gemfile.vault` against the local
OpenVox fork. Its official helper 8.0.0 uses a workspace-only dependency override
for current syntax tooling, alongside facts helper 6.3. Remove that override when
the upstream helper supports the OpenVox syntax dependency directly.
