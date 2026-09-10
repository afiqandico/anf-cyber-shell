#!/usr/bin/env bash
# ==============================================================================
# ANF CYBER SHELL — Verify Script (gate baseline)
# Menjalankan gate verifikasi aman (non-destruktif) terhadap script inti:
#   1. zsh -n                        → parse error check
#   2. version string konsisten      → 1.0.1-cyber
#   3. alias /cmd -> anf_<fn> mapping (setiap entri _ANF_CMD_DESC punya fungsi)
#   4. smoke test command inti aman (hash/encode/status) di subshell
#   5. kotak banner/help sejajar (lebar dihitung per karakter)
#   6. lookup binary tahan-alias (tanpa `command -v <nama-command>`)
#   7. anf_hermes_locate -> path executable nyata (jika hermes terpasang)
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
EXPECT="1.0.1-cyber"
if [[ "$V" == "$EXPECT" ]]; then ok "ANF_VERSION=$V"; else bad "ANF_VERSION=$V (harus $EXPECT)"; fi

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

# 7) Kotak banner/help sejajar — lebar dihitung per KARAKTER (bukan byte),
#    jadi perbandingannya via python3. Kalau python3 tidak ada, gate dilewati.
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

# 8) Lookup binary tahan-alias. PITFALL: setiap command ANF didaftarkan sebagai
#    alias nama polos, sehingga `command -v <nama-command>` mengembalikan TEKS
#    ALIAS (bukan path) → cek tool selalu lolos & teks alias ikut dieksekusi.
ALIASBUG="$(grep -nE 'command -v (hermes|amass|gobuster|nikto|suricata|whatweb|whois|stat|tor)([^a-z_-]|$)' "$F" | grep -v ':[0-9]*: *#' || true)"
if [[ -z "$ALIASBUG" ]]; then ok "lookup binary tahan-alias"; else bad "masih ada command -v bentrok alias: $ALIASBUG"; fi

# 9) Fungsional: anf_hermes_locate harus menghasilkan path executable nyata.
if command -v hermes >/dev/null 2>&1; then
  HPATH="$(timeout 30 zsh -c "source '$F' >/dev/null 2>&1; anf_hermes_locate >/dev/null 2>&1; print -r -- \$HERMES_BIN" 2>/dev/null)"
  if [[ "$HPATH" == /* && -x "$HPATH" ]]; then ok "anf_hermes -> $HPATH"; else bad "anf_hermes_locate -> '$HPATH'"; fi
else
  echo "  [SKIP] hermes tidak terpasang"
fi

echo
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
