<?php
/* github-tools POST handler.
 *
 * Actions:
 *   (default) save  - write git name/email to the flash gitconfig; if a token is
 *                     supplied, log gh in (token via stdin, never on argv) and wire
 *                     it up as git's HTTPS credential helper.
 *   logout          - sign gh out and delete the stored token.
 *
 * The token is never written to argv, logs, or the response body.
 */

header('Content-Type: text/plain; charset=utf-8');

$plugin  = "github-tools";
$bootDir = "/boot/config/plugins/$plugin";
$ghDir   = "$bootDir/gh";
$gitcfg  = "$bootDir/gitconfig";

/* --- CSRF --- */
$expected = @parse_ini_file('/var/local/emhttp/var.ini')['csrf_token'] ?? '';
$got      = $_POST['csrf_token'] ?? '';
if ($expected === '' || !hash_equals($expected, (string)$got)) {
    http_response_code(403);
    exit("Invalid CSRF token. Reload the page and try again.\n");
}

@mkdir($ghDir, 0700, true);

/* PATH must include /usr/bin so gh/git resolve under proc_open's clean env. */
$baseEnv = ['GH_CONFIG_DIR' => $ghDir, 'PATH' => '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'];

function gt_exec(string $cmd, array $env, ?string $stdin = null): array {
    $descr = [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']];
    $proc = proc_open($cmd, $descr, $pipes, null, $env);
    if (!is_resource($proc)) return [1, "failed to start: $cmd"];
    if ($stdin !== null) fwrite($pipes[0], $stdin);
    fclose($pipes[0]);
    $out = stream_get_contents($pipes[1]); fclose($pipes[1]);
    $err = stream_get_contents($pipes[2]); fclose($pipes[2]);
    return [proc_close($proc), trim($out . $err)];
}

$action = $_POST['action'] ?? 'save';

/* --- logout --- */
if ($action === 'logout') {
    gt_exec('gh auth logout --hostname github.com', $baseEnv);
    @unlink("$ghDir/hosts.yml");
    exit("Signed out of GitHub.\n");
}

/* --- save --- */
$msgs = [];

/* git identity. Strip CR/LF to avoid gitconfig/shell smuggling; git itself does
   the ini-quoting, escapeshellarg covers the shell. */
$name  = trim(str_replace(["\r", "\n"], '', (string)($_POST['git_name'] ?? '')));
$email = trim(str_replace(["\r", "\n"], '', (string)($_POST['git_email'] ?? '')));

if ($name !== '') {
    gt_exec('git config --file ' . escapeshellarg($gitcfg) . ' user.name ' . escapeshellarg($name), $baseEnv);
    $msgs[] = "Set git user.name.";
}
if ($email !== '') {
    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
        http_response_code(400);
        exit("Invalid email address.\n");
    }
    gt_exec('git config --file ' . escapeshellarg($gitcfg) . ' user.email ' . escapeshellarg($email), $baseEnv);
    $msgs[] = "Set git user.email.";
}

/* GitHub token (optional). */
$token = (string)($_POST['gh_token'] ?? '');
if ($token !== '') {
    if (!preg_match('/^[A-Za-z0-9_]{20,255}$/', $token)) {
        http_response_code(400);
        exit("That doesn't look like a GitHub token (expected 20+ chars, letters/digits/underscore).\n");
    }
    [$code, $out] = gt_exec('gh auth login --with-token --hostname github.com', $baseEnv, $token);
    if ($code !== 0) {
        http_response_code(400);
        exit("GitHub login failed: " . htmlspecialchars($out) . "\n");
    }
    @chmod("$ghDir/hosts.yml", 0600);
    gt_exec('gh auth setup-git', $baseEnv);
    $msgs[] = "Logged in to GitHub and configured git credential helper.";
}

if (!$msgs) $msgs[] = "Nothing to change.";
echo implode("\n", $msgs) . "\n";
