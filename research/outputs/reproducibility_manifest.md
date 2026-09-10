# Reproducibility Manifest — ANF Cyber Shell

**Versi:** 1.0.1-cyber
**Tanggal verifikasi:** 2026-09-10
**Command:** `make verify` (atau `bash scripts/verify.sh`)

## Baseline gates (semua PASS, non-destruktif)
| # | Gate | Metode | Status |
|---|------|--------|--------|
| 1 | Parse syntax zsh | `zsh -n code/anf_cyber_shell.zsh` | ✅ |
| 2 | Versi konsisten | `ANF_VERSION == 1.0.0-cyber` | ✅ |
| 3 | Cache dir terpisah | `~/.cache/anf-cyber` (tidak menabrak research) | ✅ |
| 4 | Mapping `/cmd`→fungsi | setiap entri `_ANF_CMD_DESC` punya `anf_<cmd>` | ✅ (utuh) |
| 5 | Smoke command inti | `encode test`→`dGVzdA==`, `hash abc`→MD5 `90015098...` | ✅ |
| 6 | Launcher hash | `anf-cyber hash abc` | ✅ |
| 7 | Launcher help | kategori `C2 Framework` tampil | ✅ |
| 8 | Kotak banner/help sejajar | lebar per karakter (python3), `anf_help` + `anf_banner` | ✅ (2 kotak, 0 misaligned) |
| 9 | Lookup binary tahan-alias | tidak ada `command -v <nama-command>` di script inti | ✅ |
| 10 | `anf_hermes` fungsional | `anf_hermes_locate` → path executable nyata (skip bila hermes absen) | ✅ |

## Bugfix v1.0.1-cyber (2026-09-10)
| Gejala | Akar masalah | Perbaikan | Bukti |
|--------|--------------|-----------|-------|
| Border banner & judul `help` miring (border kanan banner hilang) | Border `═══` hardcoded, judul memuat `${ANF_VERSION}` | Helper `_anf_box` (lebar dihitung dari isi), dipakai di 7 tempat | 2 kotak, 0 misaligned |
| `hermes` dari dalam ANF → `command not found: alias hermes=anf_hermes` | Command ANF terdaftar sebagai alias nama polos → `command -v hermes` mengembalikan TEKS ALIAS, bukan path | `_anf_which` (`whence -p`) / `_anf_has_bin`; dipakai di `anf_hermes_locate`, `anf_gen`, `anf_doctor`, wrapper tool (`amass`, `gobuster`, `nikto`, `whatweb`, `suricata`, `whois`) | `anf hermes --version` → `Hermes Agent v0.21.0` |
| Cek tool di `anf_doctor` selalu ◎ (false-positive) | idem (alias menutupi hasil pencarian binary) | loop doctor pakai `_anf_has_bin` | `amass`/`gobuster`/`suricata` → `MISSING` jujur |
| `ensure` tampil di help tapi `anf ensure` → command tidak dikenal | Merge research→cyber membawa entri `_ANF_CMD_DESC` tanpa definisi `anf_ensure` (gate #4 merah sejak merge; klaim manifest v1.0.0 "mapping utuh" salah) | `anf_ensure` diport verbatim dari ANF Research Shell (+ `_anf_has_bin`) | `make verify` → PASS=10 FAIL=0 |

Backup pra-fix: `research/archive/anf_cyber_shell_v1.0.0-cyber_pre-fix-2026-09-10.zsh`
(sha256 `bccd633bb6272370fd53df53ca334edb75118a24d4e654235adff51f4e6cc731`, 130033 B).

## Selftest
- `anf-cyber selftest` → **PASS 16 / FAIL 0**.

## Portable install (E2E)
- `./install.sh --prefix /tmp/...` → launcher jalan dari prefix terisolasi
  (`…/usr/lib/anf-cyber/anf_cyber_shell.zsh`), hash + version benar. Self-contained.

## Sumber kebenaran (origin)
- Basis diturunkan **verbatim** dari arsip penulis:
  `~/Documents/Archive/ANF-cyber-modules-v1.6/anf_research_shell_v1.6.0_FULL_local.zsh`
  (snapshot ANF v1.6.0 pra-split, modul cyber lengkap).
- Modifikasi atas basis (rebrand promo saja, fungsi tidak dihapus):
  header/banner/help → cyber-first, `ANF_VERSION=1.0.0-cyber`, cache dir → `anf-cyber`.

## PITFALL tercatat (verify.sh)
- **Jangan grep langsung di pipe dengan `set -o pipefail`**: `cmd | grep -q` → grep
  exit dini → SIGPIPE → writer exit 141 → pipefail = FAIL palsu. Fix: capture output
  ke variabel dulu, baru `[[ var == *pat* ]]`.
- **Alias shell menutupi hasil `command -v`**: setiap command ANF didaftarkan sebagai
  alias **nama polos** (`hermes=anf_hermes`), sehingga `command -v hermes` di dalam
  sesi ANF mengembalikan TEKS ALIAS, bukan path binary — cek tool jadi selalu lolos
  dan string alias itu ikut dieksekusi. Fix: `whence -p` via helper `_anf_which` /
  `_anf_has_bin`. Gate #9 menjaga regresi ini.

## Disclaimer
Command berbahaya (autopwn, suricata real, priv-esc, persist, password-spray)
**tidak dieksekusi** oleh gate — hanya untuk lab/lingkungan berizin.
