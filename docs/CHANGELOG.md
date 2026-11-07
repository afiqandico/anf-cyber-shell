# CHANGELOG — ANF Cyber Shell

## Unreleased — publication prep (2026-11-06)

The repository was prepared for public release. No command behaviour changed.

| Change | Reason | Evidence |
|-----------|--------|-------|
| Removed 3 duplicate function definitions (`anf_osint_email`, `anf_autopwn`, `anf_sysinfo` — stale copies already *shadowed* by the later definitions) | `grep -c '^anf_[a-z_]*()'` reported 108 although there were only 105 unique names; dead duplicates mislead the audit | 108 → **105** definitions = 105 unique names; `make verify` still `PASS=15 FAIL=0` |
| `install.sh`: initialise `CFG_DIR` before the `if` block | `./install.sh --prefix X --skip-config` failed with `CFG_DIR: unbound variable` (exit 1) even though the install succeeded | before: `line 49: CFG_DIR: unbound variable`; after: exit 0 |
| `README.md` rewritten in English | Portfolio publication requirement: international audience | numbers re-measured (9,251 zsh lines, 105 functions, 110 commands/14 groups) |
| Added `.github/workflows/ci.yml` | The `make verify` gate must run in CI, not only locally | `zsh -n` on all files + `make verify` on `ubuntu-latest` |
| Redacted absolute local paths (`/home/afiq/...`, `~/Documents/...`) in `README.md`, `NOTICE.md`, `docs/CHANGELOG.md`, `research/outputs/` | Publication hygiene: the home directory layout need not be exposed | `grep -rIn '/home/afiq\|~/Documents'` → 0 hits outside `research/archive/` |

## v1.0.4-cyber (Anti-collision: aliases no longer override binaries/basic tools — 2026-11-06)

**Theme: `anf` stopped "hijacking" other command names.** Before this, the ANF shell silently
replaced `stat`, `install`, `proxy`, `whois`, `nikto`, `gobuster`, `whatweb`, `tor`,
`hermes` — and (inside the interactive shell) `ls`, `cat`, `grep`, `less`, `cd`, `fd`, `log`.

| # | Old behaviour | v1.0.4 behaviour | Evidence |
|---|----------------|-----------------|-------|
| 1 | `_ANF_CMD_NAMES` aliases were created for every name, including those with a binary in PATH | the alias is **skipped** when `${commands[<name>]}` exists; the name is recorded in `_ANF_SHADOWED` | gate #11 `bentrok=0`; `anf config` → `Tanpa alias (bentrok biner): 9 nikto, tor, stat, …` |
| 2 | `ls`/`cat`/`grep`/`less`/`cd`/`fd`/`log` were replaced (eza/bat/rg/zoxide/lnav) every session | SECTION 13 became **opt-in**: `ANF_UX_ALIASES=0` (default) = the shell behaves like plain zsh | gate #11 `ux_ls=0`; `alias ls` empty |
| 3 | `hermes` inside ANF pointed at `anf_hermes`, not the Hermes CLI | `whence -p hermes` → `~/.local/bin/hermes` | runtime test: `stat=/usr/bin/stat hermes=~/.local/bin/hermes` |

How to use it after the change:
- ANF commands whose names collide: `anf stat file.csv`, `anf whois domain`, `anf install pkg` (the dispatcher is unaffected by aliases).
- ANF commands that do not collide can still be called short inside the ANF shell: `scan`, `help`, `run`, `doctor`.
- Want the old UX aliases back: `export ANF_UX_ALIASES=1` in `~/.config/anf-cyber/anfrc`.

### Additions after the initial commit (found during real use)

| Symptom | Root cause | Fix |
|--------|--------------|-----------|
| Entry animation stopped at **103%** | the loop ran 4 phases × 8 steps (`_anf_t` maximum 32) but the divisor was hardcoded to `31` | the divisor is computed from the step count: `_anf_steps=$(( ${#_anf_phases[@]} * 8 ))` → maximum **100%**, full bar 26/26 |
| The repo `bin/anf` lagged behind the installed launcher | the launcher was edited directly in `~/.local/bin/anf` (126→128 lines: animation + `research` door) without being copied back | the launcher was fixed and then **copied to `bin/anf`**; gate #14 compares the two (`cmp -s`) and fails on drift |


## v1.0.3-cyber (Hygiene: dead code + symlink race + umask — 2026-11-06)

**Theme: clear the F-E/F-F/F-G/F-I audit findings. No command behaviour changed.**

| # | Finding | Fix | Evidence |
|---|--------|-----------|-------|
| 1 | F-E: `anf_c2_decode` wrote `/tmp/exfil_$(date +%H%M%S).bin` (guessable name, symlink-prone in multi-user `/tmp`) | `mktemp "${TMPDIR:-/tmp}/anf-exfil-XXXXXX.bin"` | gate #11 (0 patterns matching `> /tmp/<fixed-name>`) |
| 2 | F-F: cache `700` but its children `775`/`664` because the login umask was `002` | `umask 077` in `anfrc` (read by the launcher before the lib) + retroactive `chmod 700/600` | gate #12 (0 group/other-accessible entries) |
| 3 | F-G: 4 `alias "/$_cmd"` blocks — dead in zsh, misleading for the audit | removed; a single plain-name alias loop at the end of the file still works | gate #11 (`0 alias "/"`), `help`/`scan` still work |
| 4 | F-I: a `matrix` descriptor with no `anf_matrix` function (orphan entry, inactive at runtime) | the descriptor line was removed | audit harness: static 130 lines, orphans `[]`, runtime 110 keys / 0 without a function |

Note: `anf_run` was moved to **before** the alias loop (v1.0.2 put it at the end of the file so `run` never received a plain-name alias). `anf run` dispatch itself is unaffected.


## v1.0.2-cyber (Controlled passthrough `anf run` — 2026-11-06)

**Theme: one explicit door for external commands, after a static audit proved the old dispatcher had no passthrough at all.**

### Features
| # | Change | Reason | Evidence |
|---|-----------|--------|-------|
| 1 | `anf run -- <cmd> [args]` (`anf_run`) | The only way to run an external command, without adding new capability: no `eval`, `--` is stripped, empty arguments rejected, the exit code is forwarded, every call is logged to `$AF_LOG_FILE` | gate #11 + 3 manual gates |
| 2 | `Passthrough:run` help category | A new command must be discoverable through `help`, not hidden | `anf help` shows the Passthrough block |

### Security notes (static audit result)
- `"$@"` is not re-parsed → ANF aliases (`stat`, `install`, `proxy`, …) are **not** invoked: `anf run -- stat -c %s` stays `/usr/bin/stat` (guarded by gate #11).
- There is no `eval` on the launcher dispatch path. The three existing `eval`s were reviewed: selftest (1816, literal string), `anf_ensure` (2659, gated by `read -q`, packages from an internal table), `zoxide init` (3031, local binary output).


## v1.0.1-cyber (Bugfix: aligned boxes + alias-resistant binary lookup — 2026-09-10)

**Theme: two bugs that surfaced in daily use — banner/help borders off by a few columns, and `hermes` failing when called from inside the shell.**

### Fix
| # | Symptom | Root cause | Fix |
|---|--------|--------------|-----------|
| 1 | Banner border & `help` title skewed (the title line wider/offset from the border); in the banner the right border vanished entirely | The `═══` border was written hardcoded assuming a fixed title length, although the title contains `${ANF_VERSION}` | Helper `_anf_box <color> "title" ["line-2" ...]` — the border width is computed from the content. Used in **7 places**: banner, `help` header, and 5 analytics headers (GuardFall, Shannon, Beaconing, Isolation Forest, ML compare) |
| 2 | `hermes` / `/hermes` from inside ANF → `command not found: alias hermes=anf_hermes` | Every ANF command was registered as a **plain-name alias**, so `command -v hermes` returned the ALIAS TEXT (not a path); that text was stored in `HERMES_BIN` and then executed | Helper `_anf_which` (uses `whence -p`, walks PATH only) + `_anf_has_bin`; used in `anf_hermes_locate`, `anf_gen`, `anf_doctor`, and the tool wrappers |

### The same bug class (every `command -v <command-name>` site) was fixed too
`amass`, `gobuster`, `nikto`, `whatweb`, `suricata`, `whois`, and the `anf_doctor` tool loop.
Previously the tool check **always passed** (false positive) even when the tool was not installed → the user got "command not found" instead of a friendly message.

### Additional fix (found by the gate during this release)
| # | Symptom | Root cause | Fix |
|---|--------|--------------|-----------|
| 3 | `ensure` showed up in `help` & `_ANF_CMD_DESC`, but `ensure`/`anf ensure` → `command tidak dikenal` | When merging research→cyber, the `ensure` entry came across but the `anf_ensure` definition was left behind in ANF Research Shell → gate #4 (`/cmd`→function mapping) had been **RED since the merge**, and the v1.0.0 manifest wrongly claimed the mapping was "intact" | `anf_ensure` was ported from `ANF-Research-Shell` (uses `_anf_has_bin`; the `[wajib]` label is now only for the `urgent=1` flag — the research version showed it for "0" as well) | `make verify` is now **PASS=10 FAIL=0** |

Honesty note: this red gate #4 was **pre-existing**, not caused by the box/alias patch — proven by running the same gate on the pre-fix backup (also `missing: ensure`).

### Verification v1.0.1-cyber
- `zsh -n` ✅; `anf selftest` → **PASS 16 / FAIL 0**.
- Boxes: `anf_help` + `anf_banner` → **2 boxes, 0 misaligned** (widths 45 & 57 columns, computed per character).
- `anf hermes --version` → `Hermes Agent v0.21.0 (2026.8.31)` (previously failed outright).
- `anf doctor` → `amass`/`gobuster`/`suricata` now honestly **MISSING** (previously always a fake ◎).
- Additional gates in `scripts/verify.sh`: **#7** aligned boxes, **#8** alias-resistant binary lookup, **#9** `anf_hermes_locate` functional (skipped when hermes is not installed).
- `make verify` → **PASS=10 / FAIL=0** (gate #4 mapping green after `anf_ensure` was ported).

### Conservative
- Pre-fix backup: `research/archive/anf_cyber_shell_v1.0.0-cyber_pre-fix-2026-09-10.zsh`
  (sha256 `bccd633bb6272370fd53df53ca334edb75118a24d4e654235adff51f4e6cc731`, 130033 B).
- No functions were removed: only 7 box blocks + 8 tool-check sites were changed, plus 3 new helpers.

## v1.0.0-cyber (Rebuilt standalone — 2026-09-09)

**Theme: ANF Cyber Shell was reborn as a standalone project focused on purple-team / cyber-ops, derived from the ANF v1.6.0 archive that carried the complete cyber modules.**

### Origin & decisions
- Before 2026-09-07: a single script **AFUCKINGCO → ANF Research Shell** containing cyber ops + research (C2, recon, OSINT, exploit, defense + math/ML).
- 2026-09-07: the cyber modules were **split off** from ANF Research Shell (to keep the research repo clean), archived to
  `ANF-cyber-modules-v1.6/anf_research_shell_v1.6.0_FULL_local.zsh` (complete pre-split snapshot).
- 2026-09-09: the standalone project **ANF-Cyber-Shell** was rebuilt (**verbatim reuse**) from that archive, with a cyber-first identity.

### Changes over the archive (basis = v1.6.0 FULL archive, 123 functions / 2285 lines)
- **Promo rebrand**: header, banner, & help title → "ANF CYBER SHELL" (purple-team focus).
- **New version**: `ANF_VERSION=1.0.0-cyber` (CHANGELOG/README/manifest in sync).
- **New cache dir**: `~/.cache/anf-cyber` (does not collide with research's `~/.cache/anf`).
- **Help reorganised cyber-first**: C2, Recon, OSINT, Exploitation, Defense/Blue, Post-Exploitation, C2-Detection Analytics → front; Utilities/Integrations/Output below. All functions are still present (none removed).
- **Launcher `bin/anf-cyber`** (layered location resolution `ANF_LIB` → install → project) + idempotent `install.sh` + `anfrc.dist` + Makefile + baseline gate `scripts/verify.sh`.
- Supporting files: LICENSE (MIT), NOTICE.md (security disclaimer), cyber-first README, .gitignore (local/sensitive operation output is not tracked).

### Verification v1.0.0-cyber (run via `scripts/verify.sh` & `make verify`)
- `zsh -n` → SYNTAX OK (2286 final lines).
- `ANF_VERSION` → `1.0.0-cyber`; cache dir → `anf-cyber`.
- `/cmd` → function mapping: **every `_ANF_CMD_DESC` entry has an `anf_<cmd>` function** (intact, 0 missing).
- Smoke (non-destructive): `encode test` → `dGVzdA==`, `hash abc` → `90015098...`.
- Launcher: `anf-cyber hash abc` → correct MD5; `anf-cyber help` → **C2 Framework** category shown.

### Conservative
- The original archive in `ANF-cyber-modules-v1.6/` was **not modified** (it remains the single source of truth).
- ANF Research Shell (v1.6.1, `ANF-Research-Shell/` & `security-lab/`) was **not touched**.
- Dangerous commands (autopwn, real suricata, priv-esc, persist) are not executed by the verification gate.

---

## Pre-split history (brief; source `ANF-Research-Shell/docs/CHANGELOG.md`)
- **v15.0.0-RESEARCH** — merge of v12 ∪ v14 (61 operational functions from v12 + v14 hardening).
- **v1.0.0 – v1.6.1 ANF** — rebrand, enterprise/research study, then the cyber split (2026-09-07).
