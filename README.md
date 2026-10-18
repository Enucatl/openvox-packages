# ML-DSA OpenVox packages

Coordinated fork packages for Ubuntu 26.04 amd64. This pipeline is being validated;
no package release is trusted as a deployment candidate until its acceptance job
passes and it is promoted to latest.

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

`tests/archive.sh` exercises archive integrity. `tests/server-recipe.rb` checks
recipe changes. Source tests and installed-agent ML-DSA checks precede candidate
publication. Package acceptance exercises anonymous APT, missing-key rejection,
paired upgrade/rollback when a previous release exists, and installed-package
RSA/ML-DSA enrollment, catalogs, renewal, revocation and Vault integration.
Acceptance evidence includes disposable private identities; it is never uploaded
as public release assets. Ubuntu 24.04 and Debian/Proxmox are outside this build.
