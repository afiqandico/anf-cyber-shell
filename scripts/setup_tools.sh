#!/usr/bin/env bash
# ==============================================================================
# ANF CYBER SHELL — Setup Tools (jalankan SEKALI oleh user, dengan sudo)
# Menginstall tool cyber yang hilang dari doctor /anf-cyber:
#   apt  : amass, yara, rlwrap, suricata
#   pip  : holehe (user-level, tanpa sudo)
# Aman: idempotent (skip yang sudah ada), menampilkan tiap perintah sebelum
# eksekusi. Jalankan:  bash scripts/setup_tools.sh
# (Butuh sudo utk paket apt; sesi Hermes TIDAK bisa — jalankan di terminal kamu.)
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
  echo "    Perintah:  sudo apt-get update && sudo apt-get install -y ${apt_needed[*]}"
  # TIDAK auto-run sudo (butuh password). User jalankan manual.
  echo "    JALANKAN SENDIRI di terminal (butuh sudo):"
  echo "      sudo apt-get update"
  echo "      sudo apt-get install -y ${apt_needed[*]}"
else
  echo "==> Semua tool apt sudah ada."
fi

# --- holehe (pip user-level, tanpa sudo) -----------------------------------------
if check holehe; then
  echo "==> holehe sudah ada."
else
  echo "==> Install holehe (pip user-level, tanpa sudo):"
  echo "      python3 -m pip install --user holehe"
fi

echo
echo "Selesai merinci. Jalankan perintah sudo di atas di terminal kamu,"
echo "lalu verifikasi dengan:  anf-cyber doctor"
