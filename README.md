# github-tools — git + GitHub CLI for Unraid

An Unraid 7 plugin that adds the **GitHub CLI (`gh`)** to your server and keeps your git
identity and GitHub login working **across reboots** — so when you SSH into the box you can
clone, commit, and push without re-authenticating every time.

> Unraid 7 already ships `git`. What it doesn't ship is `gh`, and — because the OS runs entirely
> from RAM — anything you write to `~/.gitconfig` or your GitHub token store is wiped on every
> reboot. This plugin installs `gh` and stores your config on the USB flash, restoring it on each
> boot so it just keeps working.

Tested end-to-end on **Unraid 7.3.0** (install, WebGUI, SSH usage, and uninstall).

## Features

- Installs the GitHub CLI (`gh`) as a self-contained static binary — no dependencies, no glibc
  surprises.
- Persists your git identity (`user.name` / `user.email`) and your `gh` auth token to the flash
  drive, surviving reboots.
- Wires `gh` in as git's HTTPS credential helper, so `git push` over HTTPS uses your token.
- Simple WebGUI page (**Settings → Utilities → GitHub Tools**) to set identity and paste a token.
- Works fully over SSH; the GUI is optional.
- Clean uninstall that optionally keeps your config for next time.

## Install

In the Unraid web UI: **Plugins → Install Plugin**, and paste this URL:

```
https://raw.githubusercontent.com/netarcx/unraid-github-tools/main/github-tools.plg
```

## Configure

Open **Settings → Utilities → GitHub Tools**:

- **Name / Email** — your git identity, written to the global (flash-backed) `~/.gitconfig`.
- **Token** — a GitHub [Personal Access Token](https://github.com/settings/tokens). It logs the
  `gh` CLI in and is set up as git's HTTPS credential helper. Leave blank to keep the existing
  token; use **Sign out of GitHub** to remove it.

Everything also works from the command line over SSH:

```bash
gh --version
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
echo "$YOUR_TOKEN" | gh auth login --with-token   # GH_CONFIG_DIR is preset for you
gh auth setup-git
```

## How persistence works

Unraid's OS lives in RAM and is rebuilt from the USB flash on every boot. The plugin keeps the
source of truth on flash and restores the volatile pieces at each boot:

| Lives in RAM (rebuilt each boot)                                   | Lives on flash (persists)                                              |
| ------------------------------------------------------------------ | ---------------------------------------------------------------------- |
| `/usr/bin/gh`, the WebGUI, `/root/.gitconfig`, `/root/.config/gh`  | `/boot/config/plugins/github-tools/` (cached package, gitconfig, token) |

On boot the plugin reinstalls `gh` from the cached package (no network required) and re-creates
the symlinks from `/root` to the flash copies, so your config and login are always there.

## Security note

Your GitHub token is stored **in cleartext on the USB flash drive** — Unraid has no encrypted
store for this. Recommendations:

- Prefer a **fine-grained PAT** scoped to only the repositories you need.
- Revoke the token from GitHub if the flash drive is ever lost or replaced.
- Uninstalling keeps the token on flash by design (so reinstalling restores it). To purge it,
  delete `/boot/config/plugins/github-tools/`.

## Uninstall

Remove it from **Plugins** in the web UI (or `plugin remove github-tools.plg` over SSH). This
removes `gh`, the symlinks, and the profile script, but keeps your identity/token on flash. Delete
`/boot/config/plugins/github-tools/` to fully purge.

## Build from source

The package is a Slackware `.txz` containing the `gh` binary and the WebGUI files. Build it on any
Linux host (no Slackware needed):

```bash
GH_VERSION=2.74.2 ./build/make-package.sh 2026.05.28
# -> dist/github-tools-2026.05.28-x86_64-1.txz  (+ its SHA256)
```

Builds are reproducible: identical inputs produce an identical SHA256.

## Releasing (maintainers)

Run the **Release plugin** GitHub Action with a `version` (e.g. `2026.05.28`) and a `gh_version`.
It builds the package, stamps `github-tools.plg` with the version/SHA256/repo, commits the `.plg`,
and publishes a GitHub Release with the `.txz` attached. The plugin's raw `.plg` URL then always
points at a matching package.

See [`CLAUDE.md`](CLAUDE.md) for architecture and internals.

## License

[MIT](LICENSE).
