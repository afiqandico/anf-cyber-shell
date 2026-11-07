#!/usr/bin/env bash
# ==============================================================================
# ANF CYBER SHELL — Setup Tools (run ONCE by the user, with sudo)
# Installs the cyber tools missing from the doctor /anf-cyber:
#   apt  : amass, yara, rlwrap, suricata
#   pipx : holehe (automatic, isolated; already installed)
# Safe: idempotent (skips what exists), prints each command before executing it.
# Run:  bash scripts/setup_tools.sh
# (apt needs sudo → run the printed commands in your own terminal;
#  a non-interactive Hermes session CANNOT sudo because it needs a password.)
# ==============================================================================
set -uo pipefail

echo "== ANF Cyber Shell — Setup Tools =="

check() { command -v "$1" >/dev/null 2>&1; }

# --- apt packages (needs sudo) -------------------------------------------------
apt_needed=()
for t in amass yara rlwrap suricata; do
  check "$t" || apt_needed+=("$t")
done
if (( ${#apt_needed[@]} > 0 )); then
  echo "==> Install apt: ${apt_needed[*]}"
  echo
  echo "    JALANKAN SENDIRI di terminal kamu (butuh sudo):"
  echo "      sudo apt-get update"
  echo "      sudo apt-get install -y ${apt_needed[*]}"
  echo
else
  echo "==> Semua tool apt sudah ada."
fi

# --- holehe (pipx user-level, no sudo) ------------------------------------------
if check holehe; then
  echo "==> holehe sudah ada."
else
  echo "==> Install holehe (pipx, venv terisolasi, tanpa sudo):"
  echo "      pipx install holehe"
fi

echo
echo "Selesai. Setelah jalankan perintah sudo, verifikasi dengan:  anf-cyber doctor"