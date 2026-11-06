# ANF Shell

**A zsh workbench that puts a security workflow behind one auditable dispatcher.**

[![verify](https://github.com/afiqandico/anf-cyber-shell/actions/workflows/ci.yml/badge.svg)](https://github.com/afiqandico/anf-cyber-shell/actions/workflows/ci.yml)
![license](https://img.shields.io/badge/license-MIT-blue)

`anf-cyber` loads one library, exposes every operation as a subcommand, keeps all
artefacts in a per-workspace directory, and logs what it did. The core is a single
zsh file; the CLI is a thin launcher on top of it.

Version `1.0.4-cyber` · MIT · one author · built for Linux (tested on Ubuntu, zsh 5.9).

---

## What this is, and what it is not

I would rather state the boundaries up front than have a reviewer discover them.

| This is | This is not |
|---|---|
| A dispatcher + artefact layout + audit trail over ~20 external security CLIs | A new scanner, exploit engine, or C2 implementation |
| Offensive commands that wrap `nmap`, `nuclei`, `hydra`, `ncrack`, `ssh`, `linpeas`, `subfinder`, `holehe` … | Weaponised tooling — every offensive command calls a binary you installed and fails closed if it is absent |
| A command guard (*GuardFall v2*) that canonicalises and rejects 8 classes of shell-injection / destructive patterns before passthrough execution | A sandbox or a security boundary |
| Statistical C2-detection analytics in Python (Shannon entropy + bootstrap CI, chi-square/Jitter/R(1) beaconing, Isolation Forest, ROC sweep) | A validated detector with published accuracy claims |
| A verification gate of 15 automated checks that runs in CI | A unit-test suite — see *Known limitations* |

Offensive modules are intentionally thin. `autopwn` is a full-port `nmap` pass
followed by an MSF auxiliary scan and `nuclei`; `priv-esc` runs `linpeas`;
`password-spray` shells out to `hydra`/`ncrack`. They orchestrate other people's
tools — the engineering here is in the dispatch layer, the guard, and the
artefact/audit model, not in novel exploitation.

## Measured size

All numbers below were produced by running the commands shown, on the published
tree — not estimated:

```bash
grep -h "^anf_[a-z_]*()" code/*.zsh | wc -l        # 105
find . -name '*.zsh' -not -path './.git/*' | xargs wc -l | tail -1   # 9251 total
```

| Metric | Value |
|---|---|
| zsh lines (all `*.zsh`, excl. `.git`) | **9,251** |
| Subcommand functions (`anf_*`) | **105** |
| Registered commands in the dispatch table | **110** across **14** groups |
| Files that make up the runtime path | 3 (`code/anf_cyber_shell.zsh`, `bin/anf-cyber`, `code/anfrc.dist`) |
| Checks in `make verify` | **15** (all passing on the published commit) |

## Why it exists

Working a lab or an engagement from a plain shell has three recurring problems:
output lands wherever the last `tee` put it, the tool call sequence lives only in
scrollback, and there is no record of what was run. ANF Shell addresses those
three things and nothing more:

1. **One namespace.** 110 commands, one prefix, `anf-cyber <cmd>` or `/cmd` inside
   the interactive shell. No memorising per-tool flag soup for routine steps.
2. **One artefact root.** Everything a command produces goes to
   `~/.cache/anf-cyber/workspaces/<workspace>/{scans,notes,loot,report_*}.md` — so
   a session can be reconstructed, diffed, and handed to someone else.
3. **One audit trail.** Every passthrough command is canonicalised by GuardFall v2
   and written to a JSONL audit log with an `ALLOWED` / `BLOCKED:<rule>` decision.

## Install

Requires `zsh` ≥ 5.8, `bash`, and `python3` (analytics, guard benchmark).
`git` is needed only for the clone.

```bash
git clone https://github.com/afiqandico/anf-cyber-shell.git
cd anf-cyber-shell
./install.sh --prefix "$HOME/.local"     # no root needed
export PATH="$HOME/.local/bin:$PATH"
```

`install.sh` copies the launcher to `<prefix>/bin/anf-cyber`, the core library to
`<prefix>/lib/anf-cyber/`, and seeds `~/.config/anf-cyber/anfrc` from
`code/anfrc.dist` **only if it does not already exist** — re-running is safe and
your config is never overwritten. Use `--skip-config` for a package-managed install.
For a system-wide install, omit `--prefix` (defaults to `/usr/local`).

## Quickstart

Verified on the published commit with `zsh 5.9 (x86_64-ubuntu-linux-gnu)`. The
loader prints a one-line banner before each command's output; it is omitted below.

```console
$ anf-cyber version
=== VERSION ===
  Version: 1.0.4-cyber

$ anf-cyber hash abc
  MD5:     900150983cd24fb0d6963f7d28e17f72
  SHA256:  ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
  SHA512:  ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f

$ anf-cyber encode hello
aGVsbG8=

$ anf-cyber help | head -12
  ── Core ──
    help                     Tampilkan help (kategorisasi)
    status                   Status target & workspace
    ...
```

Then work a target:

```bash
anf-cyber set-target lab.example.com     # RFC 2606 placeholder — use your own lab
anf-cyber workspace my-lab               # switch artefact root
anf-cyber subdomains                     # subfinder → workspaces/my-lab/scans/subdomains_*.txt
anf-cyber report                         # Markdown rollup for the workspace
anf-cyber doctor                         # what is installed, what is missing
```

`quickrecon` is the shortcut for `set-target` → `subdomains` → `scan`; note that the
`nmap` stage asks for confirmation, so when dispatched non-interactively (no TTY) it
is skipped — run `anf-cyber scan` yourself after setting the target.

Inside the interactive shell (`anf-cyber` with no arguments) the same commands are
available as `/cmd`, e.g. `/scan`, `/c2-entropy`, `/guardfall-metrics`.

## Command groups

Counts are from the dispatch table (`_ANF_CMD_DESC`, 110 entries):

| Group | n | Examples |
|---|---:|---|
| Core | 15 | `help` `status` `set-target` `workspace` `note` `doctor` `paths` `selftest` `targets` `log` |
| Passthrough | 1 | `run` (exit-code-preserving, alias-immune) |
| C2 Framework | 7 | `c2-start` `c2-stop` `c2-sessions` `c2-payload` `c2-interact` `c2-exfil` `c2-decode` |
| Recon | 14 | `scan` `subdomains` `subdomains-json` `dns` `whois` `quickrecon` `amass` `gobuster` `nikto` `whatweb` `wifisurvey` `monitor` `mac` `pilgrims` |
| OSINT | 4 | `osint-email` `osint-phone` `cloud-enum` `wayback` |
| Exploitation | 6 | `autopwn` `priv-esc` `password-spray` `pivot-socks` `port-forward` `ssh-tunnel` |
| Defense / Blue | 6 | `suricata` `yara-scan` `honeypot` `wazuh-agent` `guardfall-metrics` `benchmark-guardfall` |
| Post-Exploitation | 5 | `persist` `credentials` `screenshot-all` `clear-logs` `playbook` |
| C2 Detection Analytics | 7 | `c2-entropy` `c2-beacon-math` `c2-ml-hunt` `c2-zscore` `eval-entropy-roc` `eval-compare-ml` `eval-export-audit` |
| Network & OPSEC | 12 | `serve` `listen` `check-ip` `panic` `tor` `proxy` `encode` `decode` `hash` `uuid` `random` `clip` |
| Integrations & AI | 6 | `hermes` `hermes-locate` `hermes-set` `github` `ai-assist` `ai-log` |
| Utilities | 4 | `screenshot` `epoch` `serve-stop` `clear-ip` |
| Output | 2 | `report` `sysinfo` |
| Research & Math | 21 | `mlbench` `dataset` `plot` `stat` `csv` `sym` `sha` `exp` `bib` `paperstat` `gitx` `mvp` `envcard` … |

`anf-cyber doctor` checks which external binaries are actually present and lists
what is missing — useful before trusting any group above.

## Design notes — the failures that shaped the code

These are the parts I would actually want reviewed, because they came from bugs
that bit me in real use and are now pinned by checks in `make verify`.

**1. Aliases poisoned `command -v`.** Every ANF subcommand was registered as a
plain alias, so `command -v hermes` inside the shell returned the *alias text*
(`hermes=anf_hermes`) instead of a path. Tool-presence checks therefore always
passed, and that text got executed as a binary path. Fix: a `whence -p` helper that
only walks `PATH` (`_anf_which` / `_anf_has_bin`), plus a gate that greps for
`command -v <tool>` on the exact tool list. Gate 8 fails the build if the pattern
reappears.

**2. Aliases also shadowed real binaries.** The shell was silently replacing `stat`,
`install`, `whois`, `nikto`, `tor`, `hermes` — and `ls`/`cat`/`grep` in the
interactive session. Fix: aliases are skipped whenever `${commands[name]}` exists;
shadowed names go to `_ANF_SHADOWED` and must be invoked as `anf <cmd>`. Cosmetic
`ls`/`cat` UX is now opt-in via `ANF_UX_ALIASES=1`. Gate 11 asserts `bentrok=0`
and `ux_ls=0`.

**3. Passthrough must not go through the dispatcher's own alias table.**
`anf run -- stat -c %s file` has to reach the real `stat`, preserve the child's
exit code, and reject an empty argument list. That triple is gate 10, including a
deliberate `exit 7` round-trip.

**4. GuardFall v2 canonicalises before it judges.** Input is Unicode-normalised
(including soft hyphen and NUL stripping), quotes are stripped, then 8 rule classes
run: `$IFS` manipulation, process substitution, command substitution, destructive
(`rm -rf`, `dd if=/dev/zero`, `mkfs`/`shred`), network exfil to private IPs,
`LD_PRELOAD`-style env injection, aggressive path traversal (`../` ×3+), and fork
bombs. Each decision is written to the JSONL audit log as
`ALLOWED` or `BLOCKED:<rule>` — which is what `eval-export-audit` turns into CSV and
what `benchmark-guardfall` scores as TP/FP/FN/TN → precision/recall/F1.

**5. Hygiene gates.** Fixed filenames under `/tmp` were a symlink-race hazard
(`mktemp -d` now), aliases prefixed with `/` were silently dead, and cache files
were group/other-readable (now `umask 077`, cache `700`). Gates 12 and 13.

## Verification

```bash
make verify        # == make test == bash scripts/verify.sh
```

The gate is non-destructive by design: it never executes `autopwn`, `priv-esc`,
`persist` or a real Suricata run. It checks, in order: `zsh -n` parse; version
string; cache dir; every `/cmd` has a backing function; encode+hash smoke test;
launcher dispatch; launcher `help`; banner/help box alignment (computed per
character, not per byte, via python3); alias-safe binary lookup; `anf run`
semantics; alias/binary conflict count; temp-file and alias hygiene; `anfrc` umask
and cache permissions; launcher drift (`cmp -s` against the installed copy). Exit
code is non-zero if any check fails.

Current status on the published commit: **`RESULT: PASS=15 FAIL=0`** locally, and
**`PASS=14 FAIL=0`** in CI — the difference is check 9, which exercises the optional
`hermes` integration and reports `SKIP` when that binary is absent (CI installs only
zsh and jq). Zero failures either way.

CI (`.github/workflows/ci.yml`) installs `zsh` on `ubuntu-latest`, parses every
tracked zsh file, and runs `make verify`. No echo-only steps.

## Requirements

| Need | For |
|---|---|
| `zsh` ≥ 5.8 | core shell and launcher |
| `bash` | `install.sh`, `scripts/verify.sh` |
| `python3` | entropy/ML analytics, guard benchmark, box-alignment gate |
| `nmap`, `subfinder`, `nuclei`, `amass`, `gobuster`, `nikto`, `whatweb`, `hydra`, `ncrack`, `yara`, `suricata`, `holehe`, `linpeas`, `ffuf`, `jq` | individually — optional, per command |

Nothing is vendored. Missing tools produce a clear error from `doctor` or from the
command itself; no command pretends to have run.

## Known limitations

Stated plainly, because a portfolio repo that hides its rough edges is not evidence
of engineering judgement:

- **The core is one 9k-line file.** It works and it is gated, but it is a monolith.
  Splitting it by section (guard / recon / analytics / research) is the obvious next
  refactor.
- **No unit tests.** `make verify` is a smoke-and-invariant gate, not a test suite.
  There is no assertion coverage of individual command output formats.
- **`persist` and `clear-logs` act on the local machine only.** `persist` appends a
  `@reboot` cron line to *your* crontab; `clear-logs` truncates ANF's own log files.
  Neither touches a remote host — the command description in the dispatch table is
  broader than the implementation, and that is a naming debt I have not paid yet.
- **The C2 server is lab-grade.** It is a hardened teaching implementation
  (`subprocess.run` + `shlex` + blocklist + JSONL sessions), not something to expose
  to an untrusted network.
- **`sysinfo` dumps `env` into a file in the current directory.** Do not run it in a
  directory you will commit.
- **Detector numbers are not published results.** `benchmark-guardfall` scores a
  small hand-labelled corpus that ships in the file; treat the F1 it prints as a
  regression signal, not as a claim about real-world detection.

## Ethics and authorisation

This tooling is for **systems you own or are explicitly authorised to test**: your
own lab, a CTF, or a scoped engagement with written permission. Running recon,
credential attacks, or C2 against infrastructure you do not control is illegal in
most jurisdictions (UU ITE, CFAA, and equivalents) and is not what this repository
is for. Nothing here is a substitute for a signed scope document.

The author accepts no liability for misuse. See [`NOTICE.md`](NOTICE.md).

## Licence, authorship, disclosure

MIT — see [`LICENSE`](LICENSE). Sole author: **Afiq Andico Pangimpian**.
Development used AI assistants as tooling; that disclosure is recorded in
[`NOTICE.md`](NOTICE.md). Change history, including the bugs above and their
evidence, is in [`docs/CHANGELOG.md`](docs/CHANGELOG.md).
