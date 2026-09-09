# CHANGELOG — ANF Cyber Shell

## v1.0.0-cyber (Rebuilt standalone — 2026-09-09)

**Tema: ANF Cyber Shell dilahirkan ulang sebagai project mandiri berfokus purple-team / cyber-ops, diturunkan dari arsip ANF v1.6.0 yang memuat modul cyber lengkap.**

### Asal-usul & keputusan
- Sebelum 2026-09-07: script tunggal **AFUCKINGCO → ANF Research Shell** berisi cyber ops + riset (C2, recon, OSINT, exploit, defense + math/ML).
- 2026-09-07: modul cyber **dipisah** dari ANF Research Shell (biar repo riset bersih), diarsipkan ke
  `~/Documents/Archive/ANF-cyber-modules-v1.6/anf_research_shell_v1.6.0_FULL_local.zsh` (snapshot lengkap pra-split).
- 2026-09-09: project mandiri **ANF-Cyber-Shell** dibangun ulang (**verbatim reuse**) dari arsip tersebut, dengan identitas cyber-first.

### Perubahan atas arsip (basis = arsip v1.6.0 FULL, 123 fungsi / 2285 baris)
- **Rebrand promo**: header, banner, & judul help → "ANF CYBER SHELL" (purple-team focus).
- **Versi baru**: `ANF_VERSION=1.0.0-cyber` (sinkron CHANGELOG/README/manifest).
- **Cache dir baru**: `~/.cache/anf-cyber` (tidak menabrak `~/.cache/anf` research).
- **Help direorganisasi cyber-first**: C2, Recon, OSINT, Exploitation, Defense/Blue, Post-Exploitation, C2-Detection Analytics → front; Utilities/Integrations/Output di bawah. Semua fungsi tetap ada (tidak ada yang dihapus).
- **Launcher `bin/anf-cyber`** (resolusi lokasi berlapis `ANF_LIB` → install → project) + `install.sh` idempotent + `anfrc.dist` + Makefile + `scripts/verify.sh` gate baseline.
- Pendukung: LICENSE (MIT), NOTICE.md (disclaimer keamanan), README cyber-first, .gitignore (hasil operasi lokal/sensitif tidak di-track).

### Verifikasi v1.0.0-cyber (dijalankan via `scripts/verify.sh` & `make verify`)
- `zsh -n` → SYNTAX OK (2286 baris final).
- `ANF_VERSION` → `1.0.0-cyber`; cache dir → `anf-cyber`.
- Mapping `/cmd` → fungsi: **semua entri `_ANF_CMD_DESC` punya fungsi `anf_<cmd>`** (utuh, 0 missing).
- Smoke (non-destruktif): `encode test` → `dGVzdA==`, `hash abc` → `90015098...`.
- Launcher: `anf-cyber hash abc` → MD5 benar; `anf-cyber help` → kategori **C2 Framework** tampil.

### Konservatif
- Arsip asli di `~/Documents/Archive/ANF-cyber-modules-v1.6/` **tidak diubah** (tetap satu-satunya sumber kebenaran).
- ANF Research Shell (v1.6.1, `~/Documents/Projects/ANF-Research-Shell/` & `security-lab/`) **tidak disentuh**.
- Command berbahaya (autopwn, suricata real, priv-esc, persist) tidak dieksekusi oleh gate verifikasi.

---

## Sejarah pra-split (ringkas; sumber `ANF-Research-Shell/docs/CHANGELOG.md`)
- **v15.0.0-RESEARCH** — merge v12 ∪ v14 (61 fungsi operasional v12 + hardening v14).
- **v1.0.0 – v1.6.1 ANF** — rebrand, studi enterprise/research, lalu split cyber (2026-09-07).
