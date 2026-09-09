# Reproducibility Manifest — ANF Cyber Shell

**Versi:** 1.0.0-cyber
**Tanggal verifikasi:** 2026-09-09
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

## Disclaimer
Command berbahaya (autopwn, suricata real, priv-esc, persist, password-spray)
**tidak dieksekusi** oleh gate — hanya untuk lab/lingkungan berizin.
