# ML-DSA OpenVox packages

## Goal

Build and publish OpenVox agents and servers that use ML-DSA certificates.
ML-DSA is a post-quantum digital signature algorithm. This project supplies the
required source changes, signed APT packages, and a server container image.

## Main features

- **One tested release.** Each release uses fixed source commits. The server
  requires the exact agent version built with it.
- **Signed packages.** APT verifies the archive signature and package hashes.
  A release becomes `latest` only after all supported systems pass acceptance.
- **A ready server runtime.** The image includes the accepted packages, Java 25,
  and the cryptography libraries and settings needed for ML-DSA.
- **Separate deployment.** This project builds software. The
  [control repository](https://github.com/Enucatl/puppet-control-repo) supplies
  configuration, manages certificates, and deploys the software.

### Supported systems

All builds target **amd64**.

| System | Agent and server packages | Server image | Native FreeIPA client fixes |
| --- | --- | --- | --- |
| Ubuntu 26.04 | Yes | Yes | Yes |
| Ubuntu 24.04 | Yes | No | No |
| Debian 13, including Proxmox VE 9 hosts | Yes | No | Yes |

The FreeIPA client fixes are separate packages for curl, libcurl, and
`python3-ipalib`. See [native client installation](docs/native-client.md).

## Install packages

### 1. Add the archive key

Use the files from a trusted checkout of this repository. Verify the key through
your trusted operator channel. The full fingerprint is:

```text
775661C709ACE6F7C1CF0FF6C4B7528F03E0BB94
```

```sh
gpg --show-keys --with-fingerprint openvox-archive-keyring.asc
sudo install -d -m 0755 /etc/apt/keyrings
sudo install -m 0644 openvox-archive-keyring.asc /etc/apt/keyrings/
```

### 2. Add the APT source

Create `/etc/apt/sources.list.d/openvox-homelab.sources` with this content:

```text
Types: deb
URIs: https://github.com/Enucatl/openvox-packages/releases/latest/download/
Suites: ./
Architectures: amd64
Signed-By: /etc/apt/keyrings/openvox-archive-keyring.asc
```

Disable other OpenVox package sources to avoid conflicting package selections.
Do not disable signature or hash verification.

### 3. Select the host system

The archive contains packages for all three systems. Install the matching
preferences file **before** the first APT update. This file prevents APT from
selecting a package for another system.

| Host system | Preferences file |
| --- | --- |
| Ubuntu 26.04 | `apt/ubuntu26.04.pref` |
| Ubuntu 24.04 | `apt/ubuntu24.04.pref` |
| Debian 13 / Proxmox VE 9 | `apt/debian13.pref` |

For example, on Debian 13:

```sh
sudo install -m 0644 apt/debian13.pref /etc/apt/preferences.d/openvox-homelab
sudo apt update
apt-cache policy openvox-agent openvox-server
sudo apt install openvox-agent
```

Replace the preferences file when you upgrade the host system. The release
assets also contain these files.

For a native server installation, install `openvox-server`. APT installs its
matching agent dependency. ML-DSA requires Java 25 and explicit cryptography
provider settings; package installation does not enable them. See the runtime
settings in [the server Dockerfile](docker/server/Dockerfile). The control
repository deploys the server container below, which includes these settings.

### Upgrade or roll back

Upgrade a host agent with:

```sh
sudo apt update
sudo apt install --only-upgrade openvox-agent
```

On a native server, upgrade `openvox-server` and `openvox-agent` together.
Restart the server after an upgrade. A host package upgrade does not update a
server container; deploy a new image digest for that case.

For rollback, select a previously accepted
[release](https://github.com/Enucatl/openvox-packages/releases). Change the APT
source URI to `https://github.com/Enucatl/openvox-packages/releases/download/RELEASE/`,
with `RELEASE` replaced by its tag. Read the versions for your system from that
release's `build-manifest.json`, under `targets`.

Set `AGENT_VERSION` and `SERVER_VERSION` to those exact versions. Then run:

```sh
sudo apt update
sudo apt install --allow-downgrades "openvox-agent=$AGENT_VERSION" "openvox-server=$SERVER_VERSION"
```

On an agent-only host, omit `openvox-server`. Keep the versioned archive URI
until you intend to upgrade again. Package rollback does not restore certificate
or application state.

If a promotion changes `latest` during an APT update, APT can report a hash
mismatch. Repeat `apt update`; do not bypass the check.

## Use the server image

The image is published as `ghcr.io/enucatl/openvox-server`. It contains the
accepted Ubuntu 26.04 package pair and runs as the `puppet` user. It serves TLS
on TCP port 8140 and sends server logs to stdout.

### Select an image

Each accepted package release has a `server-image.json` asset after image
publication succeeds. Use its `image` value, which includes the registry digest,
in the deployment configuration. The digest identifies the exact image.

Tags have these meanings:

| Tag | Meaning |
| --- | --- |
| `9.1.0-mldsa.24001` | Example: upstream version 9.1.0, build 24001 |
| `9.1.0` | Image for the promoted release of that upstream version |
| `latest` | Image for the promoted package release |

Use digests for deployment and recovery. Moving tags can change. Rebuilding an
older release does not move these aliases.

### Supply configuration and persistent state

Prepare or restore the server identity before startup. Normal startup does not
create a certificate authority (CA) and fails if required keys or certificates
are missing.

Persist these directories:

| Path | Contents |
| --- | --- |
| `/etc/puppetlabs/puppet/ssl` | Server certificates and keys |
| `/etc/puppetlabs/puppetserver/ca` | CA certificates, keys, and records |
| `/opt/puppetlabs/server/data/puppetserver/server_data` | Server runtime state |
| `/opt/puppetlabs/server/data/puppetserver/jruby-gems` | Operator-installed gems |
| `/etc/puppetlabs/code` | Puppet code and deployment state |

Supply the server configuration and make state directories writable by `puppet`.
For a read-only container filesystem, also supply writable
`/run/puppetlabs/puppetserver` and `/var/log/puppetlabs/puppetserver` directories.

Do not mount over the whole `/opt/puppetlabs/server/data/puppetserver` directory.
It contains libraries and security settings that must change with the image.
Keep the packaged service definitions when you supply configuration.

For a new CA, run `puppetserver ca setup` explicitly with the same mounts and
configuration used by the server. It creates RSA identities by default. Add
`--key-type mldsa44` to create ML-DSA-44 identities. Restore or import existing
identities instead when you need to preserve trust.

## Develop and release

### Source repositories

The source commits are fixed by Git submodules in this repository.

| Source | Purpose |
| --- | --- |
| [openvox](sources/openvox) | Agent and native package recipe |
| [jvm-ssl-utils](sources/jvm-ssl-utils) | Server SSL library |
| [openvox-server](sources/openvox-server) | Server and native package recipe |
| [openvoxserver-ca](sources/openvoxserver-ca) | CA management gem |
| [jruby-openssl](sources/jruby-openssl) | ML-DSA support for server Ruby code |
| [vault](sources/vault) | Puppet module used with the server; deployed separately |

Clone all sources:

```sh
git clone --recurse-submodules git@github.com:Enucatl/openvox-packages.git
cd openvox-packages
```

After pulling changes, run `git submodule update --init --recursive`.
To change a source, create a branch in that submodule. Commit and push the source
change before you commit its new pointer here. For example:

```sh
git -C sources/openvox switch -c fix/example
# Edit and commit the source change in sources/openvox.
git -C sources/openvox push -u origin fix/example
git add sources/openvox
git commit -m "Update OpenVox source"
git push --recurse-submodules=check
```

The submodule clone URLs use HTTPS. Configure an SSH push URL locally if needed.
A source push alone does not trigger a coordinated release. Release preparation
rejects staged source pointers that differ from the coordinator commit.

### Release process

Push to coordinator `main`, or start the **Coordinated packages** workflow in
GitHub Actions. Changes limited to native client files use their separate workflow.

1. Read the committed source pins and assign a build number.
2. Build the forked gems once. Use the same artifacts in the server package and
   source tests. Build the server once and build an agent for each system.
3. Sign and publish a candidate APT archive. Keep `latest` unchanged.
4. Install and test the candidate on all three systems. Promote it only if all pass.
5. Build and publish the server image from the accepted package pair.

The server fork contains the gem installation recipe. The coordinator supplies
build versions and exact dependencies. JDK 21 builds the JRuby OpenSSL extension;
Java 25 runs the server. Source tests need disposable checkouts because they
change build configuration.

Package versions use `<upstream-version>+homelab.<build>-1+<target>`.
The build number is `GITHUB_RUN_NUMBER * 1000 + GITHUB_RUN_ATTEMPT`.
Keep the workflow counter history. Promotion rejects a version older than or
equal to the current release. The release manifest records source commits,
package versions, and checksums.

To build and test an accepted server image locally, use GitHub CLI and Docker:

```sh
bash scripts/server-image.sh latest
```

### Recover a failed release

Fix the cause, then start a new workflow run or choose **Re-run all jobs**.
If the fix changes code, start a new run; a rerun uses the original commit.

Do not choose **Re-run failed jobs** after candidate publication. It can reuse
the original build number and collide with an existing release. Leave published
assets intact. If a newer release already exists, start a new run.

An image failure leaves the accepted APT release intact. Retry the **Server image**
workflow with that release tag. Rebuilding an older release does not move the
current image aliases.

### Release credentials

| Credential | Use |
| --- | --- |
| `GITHUB_TOKEN` | Write releases; also write GHCR packages for the image publisher |
| `APT_SIGNING_KEY` secret | Encrypted archive signing subkey |
| `APT_SIGNING_PASSPHRASE` secret | Unlock the signing subkey |
| `APT_PRIMARY_FINGERPRINT` variable | Full fingerprint shown in the installation section |

Keep the primary private key and recovery backup outside Git and GitHub Actions.
Source forks do not need release or dispatch credentials.
