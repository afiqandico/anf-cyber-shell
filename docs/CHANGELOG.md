# CHANGELOG — ANF Cyber Shell

## v1.0.3-cyber (Higiene: dead code + symlink-race + umask — 2026-11-06)

**Tema: bereskan temuan audit F-E/F-F/F-G/F-I. Tidak ada perubahan perilaku command.**

| # | Temuan | Perbaikan | Bukti |
|---|--------|-----------|-------|
| 1 | F-E: `anf_c2_decode` menulis `/tmp/exfil_$(date +%H%M%S).bin` (nama bisa ditebak, rawan symlink di `/tmp` multi-user) | `mktemp "${TMPDIR:-/tmp}/anf-exfil-XXXXXX.bin"` | gate #11 (0 pola `> /tmp/<nama-tetap>`) |
| 2 | F-F: cache `700` tapi anaknya `775`/`664` karena umask login `002` | `umask 077` di `anfrc` (dibaca launcher sebelum lib) + `chmod 700/600` retroaktif | gate #12 (0 entri group/other-accessible) |
| 3 | F-G: 4 blok `alias "/$_cmd"` — mati di zsh, menyesatkan audit | dihapus; satu loop alias nama polos di akhir file tetap jalan | gate #11 (`0 alias "/"`), `help`/`scan` masih berfungsi |
| 4 | F-I: descriptor `matrix` tanpa fungsi `anf_matrix` (entri yatim, tidak aktif di runtime) | baris descriptor dihapus | harness audit: static 130 baris, yatim `[]`, runtime 110 key / 0 tanpa fungsi |

Catatan: `anf_run` dipindahkan ke **sebelum** loop alias (v1.0.2 menaruhnya di akhir file sehingga `run` tidak pernah dapat alias nama polos). Dispatch `anf run` sendiri tidak terpengaruh.


## v1.0.2-cyber (Passthrough terkontrol `anf run` — 2026-11-06)

**Tema: satu pintu eksplisit untuk perintah eksternal, sesudah audit statis membuktikan dispatcher lama tidak punya passthrough sama sekali.**

### Fitur
| # | Perubahan | Alasan | Bukti |
|---|-----------|--------|-------|
| 1 | `anf run -- <cmd> [args]` (`anf_run`) | Satu-satunya jalan menjalankan perintah eksternal, tanpa menambah kapabilitas baru: tanpa `eval`, `--` dibuang, argumen kosong ditolak, exit code diteruskan, tiap panggilan dicatat ke `$AF_LOG_FILE` | gate #11 + 3 gate manual |
| 2 | Kategori help `Passthrough:run` | Command baru harus ditemukan lewat `help`, tidak tersembunyi | `anf help` menampilkan blok Passthrough |

### Catatan keamanan (hasil audit statis)
- `"$@"` tidak di-reparse → alias ANF (`stat`, `install`, `proxy`, …) **tidak** ikut terpanggil: `anf run -- stat -c %s` tetap `/usr/bin/stat` (dijaga gate #11).
- Tidak ada `eval` di jalur dispatch launcher. Tiga `eval` yang ada sudah ditinjau: selftest (1816, string literal), `anf_ensure` (2659, digerbangi `read -q`, paket dari tabel internal), `zoxide init` (3031, keluaran biner lokal).


## v1.0.1-cyber (Bugfix: kotak sejajar + lookup binary tahan-alias — 2026-09-10)

**Tema: dua bug yang muncul di pemakaian harian — border banner/help meleset dan `hermes` gagal dipanggil dari dalam shell.**

### Fix
| # | Gejala | Akar masalah | Perbaikan |
|---|--------|--------------|-----------|
| 1 | Border banner & judul `help` miring (baris judul lebih lebar/melenceng dari border); di banner border kanan hilang sama sekali | Border `═══` ditulis hardcoded dengan asumsi panjang judul tetap, padahal judul memuat `${ANF_VERSION}` | Helper `_anf_box <warna> "judul" ["baris-2" ...]` — lebar border dihitung dari isi. Dipakai di **7 tempat**: banner, header `help`, dan 5 header analitik (GuardFall, Shannon, Beaconing, Isolation Forest, ML compare) |
| 2 | `hermes` / `/hermes` dari dalam ANF → `command not found: alias hermes=anf_hermes` | Setiap command ANF didaftarkan sebagai **alias nama polos**, jadi `command -v hermes` mengembalikan TEKS ALIAS (bukan path); teks itu disimpan ke `HERMES_BIN` lalu dieksekusi | Helper `_anf_which` (pakai `whence -p`, hanya menyisir PATH) + `_anf_has_bin`; dipakai di `anf_hermes_locate`, `anf_gen`, `anf_doctor`, dan wrapper tool |

### Kelas bug yang sama (semua situs `command -v <nama-command>`) ikut diperbaiki
`amass`, `gobuster`, `nikto`, `whatweb`, `suricata`, `whois`, dan loop tool `anf_doctor`.
Sebelumnya cek tool **selalu lolos** (false-positive) walau tool tidak terpasang → user menerima "command not found" alih-alih pesan ramah.

### Fix tambahan (ditemukan gate saat rilis ini)
| # | Gejala | Akar masalah | Perbaikan |
|---|--------|--------------|-----------|
| 3 | `ensure` tampil di `help` & `_ANF_CMD_DESC`, tapi `ensure`/`anf ensure` → `command tidak dikenal` | Saat merge research→cyber, entri `ensure` ikut masuk tapi definisi `anf_ensure` tertinggal di ANF Research Shell → gate #4 (mapping `/cmd`→fungsi) sudah **MERAH sejak merge**, dan manifest v1.0.0 keliru mengklaim mapping "utuh" | `anf_ensure` diport dari `ANF-Research-Shell` (memakai `_anf_has_bin`; label `[wajib]` kini hanya untuk flag `urgent=1` — versi research menampilkannya untuk "0" juga) | `make verify` kini **PASS=10 FAIL=0** |

Catatan kejujuran: gate #4 merah ini **pre-existing**, bukan akibat patch kotak/alias — dibuktikan dengan menjalankan gate yang sama pada backup pra-fix (juga `missing: ensure`).

### Verifikasi v1.0.1-cyber
- `zsh -n` ✅; `anf selftest` → **PASS 16 / FAIL 0**.
- Kotak: `anf_help` + `anf_banner` → **2 kotak, 0 misaligned** (lebar 45 & 57 kolom, dihitung per karakter).
- `anf hermes --version` → `Hermes Agent v0.21.0 (2026.8.31)` (sebelumnya gagal total).
- `anf doctor` → `amass`/`gobuster`/`suricata` kini jujur **MISSING** (sebelumnya selalu ◎ palsu).
- Gate tambahan di `scripts/verify.sh`: **#7** kotak sejajar, **#8** lookup binary tahan-alias, **#9** `anf_hermes_locate` fungsional (dilewati bila hermes tidak terpasang).
- `make verify` → **PASS=10 / FAIL=0** (gate #4 mapping hijau setelah `anf_ensure` diport).

### Konservatif
- Backup pra-fix: `research/archive/anf_cyber_shell_v1.0.0-cyber_pre-fix-2026-09-10.zsh`
  (sha256 `bccd633bb6272370fd53df53ca334edb75118a24d4e654235adff51f4e6cc731`, 130033 B).
- Tidak ada fungsi yang dihapus: hanya 7 blok kotak + 8 situs cek tool diubah, ditambah 3 helper baru.

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
