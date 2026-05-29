<?php
/* Read-only status fragment for the github-tools page. Reports tool versions and
   gh auth state. Never prints the token. Safe to fetch via AJAX or include inline. */

$plugin  = "github-tools";
$bootDir = "/boot/config/plugins/$plugin";
$ghDir   = "$bootDir/gh";

putenv("GH_CONFIG_DIR=$ghDir");

function gt_run(string $cmd): string {
    return trim((string)@shell_exec($cmd . " 2>&1"));
}

$gitVer = gt_run("git --version");
$ghVer  = gt_run("gh --version | head -n1");
$ghAuth = is_file("$ghDir/hosts.yml")
    ? gt_run("gh auth status --hostname github.com")
    : "Not logged in. Paste a token above to authenticate.";

$git = $gitVer !== "" ? $gitVer : "git not found (unexpected on Unraid 7)";
$gh  = $ghVer  !== "" ? $ghVer  : "gh not installed yet";

echo "<b>git:</b>  " . htmlspecialchars($git) . "\n";
echo "<b>gh:</b>   " . htmlspecialchars($gh)  . "\n";
echo "<b>auth:</b> " . htmlspecialchars($ghAuth) . "\n";
echo "<b>config:</b> stored on flash at " . htmlspecialchars($bootDir);
