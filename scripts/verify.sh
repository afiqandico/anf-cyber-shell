#!/usr/bin/env bash
# ==============================================================================
# ANF CYBER SHELL — Verify Script (gate baseline)
# Runs the safe (non-destructive) verification gates against the core script:
#   1. zsh -n                        → parse error check
#   2. version string consistent    → 1.0.4-cyber
#   3. alias /cmd -> anf_<fn> mapping (every _ANF_CMD_DESC entry has a function)
#   4. smoke test of safe core commands (hash/encode/status) in a subshell
#   5. banner/help boxes aligned (width counted per character)
#   6. alias-proof binary lookup (no `command -v <command-name>`)
#   7. anf_hermes_locate -> real executable path (when hermes is installed)
# No runtime output/results are written into any other repo. Exit 0 when all PASS.
# ==============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
F="$ROOT/code/anf_cyber_shell.zsh"
LAUNCHER="$ROOT/bin/anf-cyber"
PASS=0; FAIL=0

ok()  { echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad() { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

echo "== ANF Cyber Shell verify =="

# 1) Parse check
if zsh -n "$F" >/dev/null 2>&1; then ok "zsh -n syntax"; else bad "zsh -n syntax"; fi

# 2) Version
V="$(grep -m1 -oE 'export ANF_VERSION="[^"]+"' "$F" | sed 's/.*"\(.*\)"/\1/')"
EXPECT="1.0.4-cyber"
if [[ "$V" == "$EXPECT" ]]; then ok "ANF_VERSION=$V"; else bad "ANF_VERSION=$V (harus $EXPECT)"; fi

# 3) Cache dir
if grep -q 'ANF_CACHE_DIR.*\.cache/anf-cyber' "$F"; then ok "cache dir anf-cyber"; else bad "cache dir anf-cyber"; fi

# 4) Function <-> command mapping: every /cmd in _ANF_CMD_DESC must have a
#    function anf_<cmd with - -> _>. Verified via zsh in a subshell.
MAP=$(zsh -c "source '$F'; rc=0; for c in \${(k)_ANF_CMD_DESC}; do f=\"anf_\${c//-/_}\"; (( \${+functions[\$f]} )) || { echo \"missing: \$c\"; rc=1; }; done; exit \$rc" 2>/dev/null)
if [[ -z "$MAP" ]]; then ok "semua /cmd punya fungsi (mapping utuh)"; else bad "mapping: $MAP"; fi

# 5) Smoke test of safe commands via the launcher (in a subshell, with timeout)
SMOKE=$(timeout 30 zsh -c "source '$F'; a=\$(anf_encode test); h=\$(anf_hash abc); print \"\$a|\$h\"" 2>/dev/null)
if [[ "$SMOKE" == *"dGVzdA=="* ]] && [[ "$SMOKE" == *"90015098"* ]]; then
  ok "smoke encode+hash (non-destruktif)"; else bad "smoke encode+hash -> '$SMOKE'"; fi

# 6) Launcher: help and hash work. NOTE: never grep directly on the pipe
#    (grep -q exits early -> SIGPIPE -> launcher exit 141 -> pipefail = false FAIL).
#    Capture into a variable first, then grep.
L_HASH="$(timeout 30 zsh "$LAUNCHER" hash abc 2>/dev/null)"
if [[ "$L_HASH" == *90015098* ]]; then
  ok "launcher anf-cyber hash abc"; else bad "launcher anf-cyber hash abc"; fi
L_HELP="$(timeout 30 zsh "$LAUNCHER" help 2>/dev/null)"
if [[ "$L_HELP" == *"C2 Framework"* ]]; then
  ok "launcher anf-cyber help (kategori C2 Framework)"; else bad "launcher help (tanpa C2 Framework)"; fi

# 7) Banner/help boxes aligned — width counted per CHARACTER (not byte),
#    so the comparison runs via python3. If python3 is absent the gate is skipped.
if command -v python3 >/dev/null 2>&1; then
  BOXOUT="$(timeout 30 zsh -c "source '$F' >/dev/null 2>&1; anf_help; anf_banner" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')"
  BOXRES="$(printf '%s\n' "$BOXOUT" | python3 -c '
import sys
boxes, cur = [], []
for l in sys.stdin.read().splitlines():
    if "╔" in l:
        cur = [l]; continue
    if cur:
        cur.append(l)
        if "╚" in l:
            boxes.append(cur); cur = []
bad = [i + 1 for i, b in enumerate(boxes) if len({len(x) for x in b}) != 1]
print("MISALIGNED:" + ",".join(map(str, bad)) if bad else "OK:" + str(len(boxes)))
')"
  if [[ "$BOXRES" == OK:* ]]; then
    ok "kotak banner/help sejajar (${BOXRES#OK:} kotak)"; else bad "kotak tidak sejajar -> $BOXRES"; fi
else
  echo "  [SKIP] kotak sejajar (python3 tidak ada)"
fi

# 8) Alias-proof binary lookup. PITFALL: every ANF command is registered as a
#    bare-name alias, so `command -v <command-name>` returns the ALIAS
#    TEXT (not a path) → the tool check always passes & the alias text gets executed.
ALIASBUG="$(grep -nE 'command -v (hermes|amass|gobuster|nikto|suricata|whatweb|whois|stat|tor)([^a-z_-]|$)' "$F" | grep -v ':[0-9]*: *#' || true)"
if [[ -z "$ALIASBUG" ]]; then ok "lookup binary tahan-alias"; else bad "masih ada command -v bentrok alias: $ALIASBUG"; fi

# 9) Functional: anf_hermes_locate must produce a real executable path.
if command -v hermes >/dev/null 2>&1; then
  HPATH="$(timeout 30 zsh -c "source '$F' >/dev/null 2>&1; anf_hermes_locate >/dev/null 2>&1; print -r -- \$HERMES_BIN" 2>/dev/null)"
  if [[ "$HPATH" == /* && -x "$HPATH" ]]; then ok "anf_hermes -> $HPATH"; else bad "anf_hermes_locate -> '$HPATH'"; fi
else
  echo "  [SKIP] hermes tidak terpasang"
fi

# 10) anf_run: controlled passthrough (v1.0.2). Preserves three properties at once:
#     the exit code is passed through, `anf run -- stat` does NOT hit alias anf_stat, and
#     empty arguments are rejected with exit 1.
RUND="$(mktemp -d "${TMPDIR:-/tmp}/anf-run-gate.XXXXXX")"
cat > "$RUND/t.zsh" <<'EOS'
source "$ANF_F"
anf_run -- sh -c 'exit 7'; print -r -- "exit7=$?"
out="$(anf_run -- stat -c %s "$ANF_F" 2>/dev/null)"; print -r -- "stat=$out"
anf_run -- >/dev/null 2>&1; print -r -- "empty=$?"
EOS
RUNRES="$(ANF_F="$F" timeout 30 zsh "$RUND/t.zsh" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')"
EXPECT_BYTES="$(stat -c %s "$F")"
if [[ "$RUNRES" == *"exit7=7"* && "$RUNRES" == *"stat=$EXPECT_BYTES"* && "$RUNRES" == *"empty=1"* ]]; then
  ok "anf_run: exit code, stat asli (tanpa alias), argumen kosong ditolak"
else
  bad "anf_run tidak sesuai -> $RUNRES"
fi
rm -rf "$RUND"

# 11) Anti-clash: no ANF alias shadows a real binary, and the UX aliases
#     (ls/cat/grep/cd) are off by default; ANF commands still go through `anf <cmd>`.
CB="$(mktemp -d "${TMPDIR:-/tmp}/anf-conflict.XXXXXX")"
CONF="$(zsh -c 'source "$1" 1>"$2" 2>&1; b=0; for k in ${(k)_ANF_CMD_DESC}; do
  [[ -n ${aliases[$k]:-} && -n ${commands[$k]:-} ]] && b=$((b+1)); done
  print -r -- "bentrok=$b ux_ls=${+aliases[ls]} shadowed=$#_ANF_SHADOWED"' zsh "$F" "$CB/sink" 2>&1 | grep -E '^bentrok=')"
rm -rf "$CB"
if [[ "$CONF" == "bentrok=0 ux_ls=0"* ]]; then
  ok "anti-bentrok: 0 alias menimpa biner, UX alias off (${CONF})"
else
  bad "anti-bentrok: $CONF"
fi

# 12) Code hygiene: no writes to fixed names in /tmp (prone to symlink races) and
#     no "/"-prefixed alias (dead in zsh, only misleads audits).
TMPFIX="$(grep -nE '>[[:space:]]*"?/tmp/[A-Za-z0-9_]' "$F" | wc -l)"
SLASHA="$(grep -c 'alias "/' "$F" 2>/dev/null || true)"
if [[ "$TMPFIX" -eq 0 && "${SLASHA:-0}" -eq 0 ]]; then
  ok "hygiene: 0 temp nama tetap di /tmp, 0 alias berprefix /"
else
  bad "hygiene: tmp_nama_tetap=$TMPFIX alias_slash=${SLASHA:-0}"
fi

# 13) Runtime OPSEC: umask 077 in anfrc + no cache file/dir may be
#     accessible by group/other (gate skipped when anfrc is not on this machine).
CFG="${ANF_CONFIG:-$HOME/.config/anf-cyber/anfrc}"
if [[ -f "$CFG" ]]; then
  LOOSE="$(find "$HOME/.cache/anf-cyber" -perm /077 2>/dev/null | wc -l)"
  if grep -q '^umask 077' "$CFG" && [[ "$LOOSE" -eq 0 ]]; then
    ok "opsec: umask 077 + cache 700 (0 entri group/other-accessible)"
  else
    bad "opsec: umask_077=$((grep -c '^umask 077' "$CFG")) entri_longgar=$LOOSE"
  fi
else
  ok "opsec: anfrc belum ada, gate perms dilewati"
fi

# 15) Launcher in sync: if ~/.local/bin/anf exists, its content must match
#     bin/anf in the repo (the repo once lagged: the animation + research/cyber entry
#     existed only in the installed copy). Gate skipped when not installed.
if [[ -f "$HOME/.local/bin/anf" ]]; then
  if cmp -s "$HOME/.local/bin/anf" "$ROOT/bin/anf"; then
    ok "launcher: bin/anf == ~/.local/bin/anf"
  else
    bad "launcher: bin/anf berbeda dari ~/.local/bin/anf (drift)"
  fi
else
  ok "launcher: ~/.local/bin/anf tidak ada (gate dilewati)"
fi

echo
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
