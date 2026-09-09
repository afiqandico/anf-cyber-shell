#!/usr/bin/env bash
# ==============================================================================
# ANF CYBER SHELL — Setup Tools (jalankan SEKALI oleh user, dengan sudo)
# Menginstall tool cyber yang hilang dari doctor /anf-cyber:
#   apt  : amass, yara, rlwrap, suricata
#   pipx : holehe (otomatis, terisolasi; sudah dipasang)
# Aman: idempotent (skip yang sudah ada), menampilkan perintah sebelum eksekusi.
# Jalankan:  bash scripts/setup_tools.sh
# (apt butuh sudo → jalankan perintah yang ditampilkan di terminal kamu sendiri;
#  sesi Hermes non-interaktif TIDAK bisa sudo karena butuh password.)
# ==============================================================================
set -uo pipefail

echo "== ANF Cyber Shell — Setup Tools =="

check() { command -v "$1" >/dev/null 2>&1; }

# --- apt packages (butuh sudo) -------------------------------------------------
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

# --- holehe (pipx user-level, tanpa sudo) ---------------------------------------
if check holehe; then
  echo "==> holehe sudah ada."
else
  echo "==> Install holehe (pipx, venv terisolasi, tanpa sudo):"
  echo "      pipx install holehe"
fi

echo
echo "Selesai. Setelah jalankan perintah sudo, verifikasi dengan:  anf-cyber doctor"