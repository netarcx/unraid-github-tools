# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`github-tools` is an Unraid 7.x plugin that makes the **GitHub CLI (`gh`)** available on the
server and persists git/gh configuration across reboots. It targets the command line / SSH use
case. There is no application to run locally — the deliverable is a `.plg` installer plus a
Slackware `.txz` package consumed by Unraid's plugin manager.

## The one constraint that explains everything: RAM vs flash

Unraid's OS runs **entirely from RAM** and is rebuilt from the USB flash drive (`/boot`) on
**every reboot**. Anything written to `/usr`, `/etc`, or `/root` is volatile and gone after a
restart. Only `/boot` survives. Two consequences drive the whole design:

- **Volatile (rebuilt each boot):** `/usr/bin/gh`, the WebGUI under
  `/usr/local/emhttp/plugins/github-tools/`, `/etc/profile.d/github-tools.sh`, and the symlinks
  in `/root`. The `.plg` recreates all of these on every boot.
- **Persistent (on flash):** `/boot/config/plugins/github-tools/` holds the cached `.txz`, the
  canonical `gitconfig`, and the `gh` config/token dir. This is the source of truth.

**`git` is already part of Unraid 7** (2.47.1, with curl/perl/openssl/ca-certificates). Do **not**
add git to this plugin — it would be redundant. The plugin installs `gh` only.

## Architecture

**One packaged asset.** `github-tools-<version>-x86_64-1.txz` (attached to a GitHub Release)
contains `usr/bin/gh` + the WebGUI tree + `install/slack-desc`. Built by `build/make-package.sh`,
which downloads the upstream static `gh` binary, verifies its checksum, and repacks it (a
Slackware `.txz` is just an xz tarball of the install tree — no Slackware host needed).

**`.plg` lifecycle** (`github-tools.plg`). On install *and on every boot*, the plugin manager:
1. Caches the `.txz` on flash and `upgradepkg --install-new`s it (download skipped when the
   cached file's `<SHA256>` matches — so it works offline after first install).
2. Runs `scripts/setup.sh` to restore the volatile bits.
On uninstall (`Method="remove"`), it `removepkg`s and drops the symlinks/profile.d but **keeps**
the flash config so a reinstall restores identity + token.

**Persistence chain** (`scripts/setup.sh`, runs each boot):
- `~/.gitconfig` → symlink to `/boot/config/plugins/github-tools/gitconfig`
- `~/.config/gh` → symlink to `/boot/config/plugins/github-tools/gh` (env-independent; works for
  all shells, not just login shells)
- `/etc/profile.d/github-tools.sh` exports `GH_CONFIG_DIR` (belt-and-suspenders for login shells)
- `gh auth setup-git` wires gh in as git's HTTPS credential helper (only when a token exists)

**WebGUI** (`src/.../github-tools.page` + `include/`). Utilities → GitHub Tools. `save.php` is the
only privileged endpoint: it validates CSRF (against `/var/local/emhttp/var.ini`), writes git
identity via `git config --file`, and logs gh in by feeding the token through **stdin** (never
argv/logs) to `gh auth login --with-token`. `status.php` is read-only and never prints the token.

## File map

```
github-tools.plg                         installer + update endpoint (CI stamps version/SHA/repo)
src/usr/local/emhttp/plugins/github-tools/
  github-tools.page                      WebGUI settings page (Unraid header block + PHP/HTML)
  include/save.php                       privileged POST handler (CSRF, identity, gh login)
  include/status.php                     read-only status fragment
  scripts/setup.sh                       boot-time restore of volatile state
build/make-package.sh                    builds the .txz, prints VERSION/GH_VERSION/SHA256
.github/workflows/release.yml            manual release: build, stamp .plg, commit, publish
```

The `src/` tree mirrors the package's install layout (paths under `/`), so what you see is where
files land on the server.

## Commands

```bash
# Build the package locally (defaults: today's date, pinned GH_VERSION in the script)
./build/make-package.sh
GH_VERSION=2.74.2 ./build/make-package.sh 2026.05.28   # explicit versions
# Output + SHA256 land in ./dist/

# Local static checks (no Unraid box needed)
xmllint --noout github-tools.plg
shellcheck build/make-package.sh src/usr/local/emhttp/plugins/github-tools/scripts/setup.sh
php -l src/usr/local/emhttp/plugins/github-tools/include/save.php
php -l src/usr/local/emhttp/plugins/github-tools/include/status.php
tar tJf dist/github-tools-*.txz          # confirm usr/bin/gh + emhttp tree present

# Release: Actions → "Release plugin" → run with version + gh_version inputs.
```

## `.plg` gotchas (read before editing the .plg)

- **LF only.** CRLF anywhere in the `.plg` or shipped scripts breaks install. `make-package.sh`
  strips CRLF from packaged scripts defensively.
- **Inline scripts are wrapped in `<![CDATA[ ... ]]>`** so shell `&`, `&&`, `2>&1`, `<`, `>` are
  not parsed as XML. Entity refs (`&name;`, `&version;`) do **not** expand inside CDATA — that's
  why the inline blocks hardcode `github-tools` paths.
- **End every inline block with `exit 0`** — a non-zero exit aborts the whole install.
- **Use `<SHA256>`**, not `<MD5>` (preferred and takes precedence).
- Entity values may reference other entities (`pluginURL` references `&github;`) — this expands
  at use time and is valid.
- The release **tag must equal the bare `version`** (no `v` prefix) because `packageURL` is
  `.../releases/download/&version;/&txzName;`.

## Verifying a change actually works

Local static checks (above) catch syntax/packaging errors but **cannot** validate runtime
behavior — that requires a real Unraid 7 server (or VM). On-device checklist:

1. Plugins → Install Plugin → paste the raw `.plg` URL (or drop the `.plg` in
   `/boot/config/plugins/`). Confirm it installs.
2. SSH in: `which gh && gh --version && git --version`.
3. GUI: set name/email + paste a PAT → Apply. Confirm `gh auth status` shows logged-in and
   `git config --global --list` shows the identity.
4. `git clone` a private repo over HTTPS (exercises the gh credential helper).
5. **Reboot**, SSH back in, re-check steps 2–3 — everything must persist. This is the real test
   of the flash/symlink design.

## Placeholders to resolve before first release

- `github` entity in `github-tools.plg` is set to `netarcx/unraid-github-tools`; the release
  workflow also re-stamps it from `${{ github.repository }}` on every build.
- `support=` forum-thread URL in the `.plg`.
- `images/github-tools.png` is a placeholder icon (replace with a real one; the menu itself uses
  the FontAwesome `github` icon).
