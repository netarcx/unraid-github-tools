#!/bin/bash
#
# github-tools setup
#
# Runs on every boot (and on install) from the .plg. Unraid's OS lives in RAM and
# is rebuilt from the USB flash on each reboot, so anything under /root, /usr or
# /etc is volatile. This script restores the volatile bits from the canonical copies
# that live on the flash drive under /boot/config/plugins/github-tools.
#
# Idempotent by design: safe to run repeatedly. Always exits 0 so a hiccup here
# never aborts the plugin install.

PLUGIN="github-tools"
BOOT_DIR="/boot/config/plugins/${PLUGIN}"
GITCONFIG="${BOOT_DIR}/gitconfig"
GH_DIR="${BOOT_DIR}/gh"
PROFILE_D="/etc/profile.d/${PLUGIN}.sh"

mkdir -p "${BOOT_DIR}" "${GH_DIR}"
chmod 700 "${GH_DIR}"

# Canonical git config lives on flash; create an empty one on first run so the
# symlink target always exists.
[ -f "${GITCONFIG}" ] || : > "${GITCONFIG}"

# /root is RAM: point ~/.gitconfig and ~/.config/gh at the flash copies so edits
# (git config --global, gh login) write straight through to persistent storage.
ln -sf "${GITCONFIG}" /root/.gitconfig
mkdir -p /root/.config
# Drop a stale real directory first; -n avoids nesting the link inside an existing
# symlinked dir. (On a fresh RAM boot neither should exist, but be idempotent.)
[ -d /root/.config/gh ] && [ ! -L /root/.config/gh ] && rm -rf /root/.config/gh
ln -sfn "${GH_DIR}" /root/.config/gh

# Belt-and-suspenders for non-root / login shells that don't use /root.
cat > "${PROFILE_D}" <<EOF
# Added by ${PLUGIN}. Points the GitHub CLI at its persistent config on the flash.
export GH_CONFIG_DIR="${GH_DIR}"
EOF
# Slackware's /etc/profile only sources profile.d scripts that are executable.
chmod 755 "${PROFILE_D}"

# Lock down the token file if a login has been performed.
[ -f "${GH_DIR}/hosts.yml" ] && chmod 600 "${GH_DIR}/hosts.yml"

# If we're authenticated, wire gh up as git's HTTPS credential helper so
# `git clone/push` over HTTPS just works. Writes into the (flash-backed) global
# gitconfig, so it persists; re-running is harmless.
if [ -f "${GH_DIR}/hosts.yml" ] && command -v gh >/dev/null 2>&1; then
    GH_CONFIG_DIR="${GH_DIR}" gh auth setup-git >/dev/null 2>&1
fi

exit 0
