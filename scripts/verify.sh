#!/usr/bin/env bash
# ==============================================================================
# ANF CYBER SHELL — Verify Script (gate baseline)
# Menjalankan gate verifikasi aman (non-destruktif) terhadap script inti:
#   1. zsh -n                        → parse error check
#   2. version string konsisten      → 1.0.0-cyber
#   3. alias /cmd -> anf_<fn> mapping (setiap entri _ANF_CMD_DESC punya fungsi)
#   4. smoke test command inti aman (hash/encode/status) di subshell
# Semua output runtime /hasil tak ditulis ke repo lain. Exit 0 jika semua PASS.
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
if [[ "$V" == "1.0.0-cyber" ]]; then ok "ANF_VERSION=$V"; else bad "ANF_VERSION=$V (harus 1.0.0-cyber)"; fi

# 3) Cache dir
if grep -q 'ANF_CACHE_DIR.*\.cache/anf-cyber' "$F"; then ok "cache dir anf-cyber"; else bad "cache dir anf-cyber"; fi

# 4) Function <-> command mapping: setiap /cmd di _ANF_CMD_DESC harus punya
#    fungsi anf_<cmd dengan - -> _>. Verifikasi via zsh di subshell.
MAP=$(zsh -c "source '$F'; rc=0; for c in \${(k)_ANF_CMD_DESC}; do f=\"anf_\${c//-/_}\"; (( \${+functions[\$f]} )) || { echo \"missing: \$c\"; rc=1; }; done; exit \$rc" 2>/dev/null)
if [[ -z "$MAP" ]]; then ok "semua /cmd punya fungsi (mapping utuh)"; else bad "mapping: $MAP"; fi

# 5) Smoke test command aman via launcher (di subshell, timeout)
SMOKE=$(timeout 30 zsh -c "source '$F'; a=\$(anf_encode test); h=\$(anf_hash abc); print \"\$a|\$h\"" 2>/dev/null)
if [[ "$SMOKE" == *"dGVzdA=="* ]] && [[ "$SMOKE" == *"90015098"* ]]; then
  ok "smoke encode+hash (non-destruktif)"; else bad "smoke encode+hash -> '$SMOKE'"; fi

# 6) Launcher: help dan hash jalan. CATATAN: jangan grep langsung di pipe
#    (grep -q exit dini -> SIGPIPE -> launcher exit 141 -> pipefail = FAIL palsu).
#    Capture dulu ke variabel, baru grep.
L_HASH="$(timeout 30 zsh "$LAUNCHER" hash abc 2>/dev/null)"
if [[ "$L_HASH" == *90015098* ]]; then
  ok "launcher anf-cyber hash abc"; else bad "launcher anf-cyber hash abc"; fi
L_HELP="$(timeout 30 zsh "$LAUNCHER" help 2>/dev/null)"
if [[ "$L_HELP" == *"C2 Framework"* ]]; then
  ok "launcher anf-cyber help (kategori C2 Framework)"; else bad "launcher help (tanpa C2 Framework)"; fi

echo
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
