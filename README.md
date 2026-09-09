# ANF Cyber Shell

**Purple-Team / Cyber-Operations Zsh Workbench — satu terminal untuk C2, recon, OSINT, exploit, defense, dan deteksi C2, dengan output terukur.**

*Rebuilt standalone dari arsip ANF v1.6.0 (yang berisi modul cyber lengkap), setelah modul cyber dipisah dari ANF Research Shell pada 2026-09-07. Identitas AWAL project ini (sebelum rebrand jadi research workbench) adalah script purple-team AFUCKINGCO → ANF.*

ANF Cyber Shell membungkus seluruh siklus operasi keamanan (recon → C2 → analitik deteksi → defense) ke satu CLI zsh yang deterministik, ter-hardening, dan teruji, berikut engine GuardFall v2 untuk sanitasi input perintah.

---

## Kenapa ANF Cyber Shell
Satu terminal tempat semua pekerjaan **purple-team** bisa dijalankan konsisten:

- **C2 Framework (hardened v2)** — server C2 pakai `subprocess.run()`+`shlex`+sandbox+minimal env; JSONL session log; graceful shutdown.
- **Analitik Deteksi C2** — Shannon entropy + bootstrap CI, beaconing (jitter/chi-square/R(1)), Isolation Forest, Z-Score, ROC sweep. Materi riset deteksi yang bisa diverifikasi.
- **Recon / OSINT** — subdomain enum, nmap scan, amass/gobuster/nikto/whatweb, dns/whois/quickrecon, osint-email/phone, cloud-enum, wayback.
- **Exploit / Post-Exploit / Pivot** — autopwn (nmap+msf+nuclei), priv-esc, password-spray, pivot-socks, port-forward, ssh-tunnel, persist, credentials.
- **Defense / Blue** — suricata IDS, yara scan, honeypot, wazuh-agent, GuardFall v2 metrics (TP/FP/F1), benchmark.
- **OPSEC** — panic (sanitize shell non-destruktif), tor toggle, encode/decode/hash, check-ip, proxy.

Jalankan `anf-cyber help` untuk daftar command per kategori; `anf-cyber selftest` untuk cek baseline; `make verify` untuk gate verifikasi.

---

## Instalasi
```bash
./install.sh                 # instal ke /usr/local/bin + config + lib
# atau tanpa root:
./install.sh --prefix "$HOME/.local"
```

## Penggunaan — satu pintu `anf`
Setelah setup (lihat di bawah), semua shell ANF diakses lewat **satu menu** `anf`:
```bash
anf               # banner menu (Research / Cyber)
anf research      # masuk ANF Research Shell (ML/math/reproducible) — launcher anf-research
anf cyber         # masuk ANF Cyber Shell (purple-team/ops)        — launcher anf-cyber
# anf <cmd>...    # (legacy) dispatch command ke Research Shell
```

### Cyber Shell langsung (`anf-cyber`)
```bash
anf-cyber                # shell interaktif (ZLE popup + banner)
anf-cyber help           # daftar command per kategori
anf-cyber set-target example.com
anf-cyber scan           # nmap -sV -sC
anf-cyber subdomains example.com
anf-cyber c2-start       # jalankan C2 server (hardened)
anf-cyber c2-entropy     # Shannon entropy + CI
anf-cyber encode hello   # base64
anf-cyber hash abc       # MD5/SHA256/SHA512
```
Di dalam shell: `/scan`, `/subdomains`, `/c2-start`, `/c2-sessions`, `/osint-email`, `/guardfall-metrics`, dst. (alias `/cmd`).

### Setup launcher unified (Research + Cyber)
```bash
# Cyber shell (repo ini)
./install.sh --prefix "$HOME/.local"          # bin/anf-cyber
install -m755 bin/anf "$HOME/.local/bin/anf"  # menu pintu unified

# Research shell (repositori FROZEN, TIDAK diubah)
~/Documents/Projects/ANF-Research-Shell/install.sh --prefix "$HOME/.local"
install -m755 ~/Documents/Projects/ANF-Research-Shell/bin/anf "$HOME/.local/bin/anf-research"
```
`.zshrc` tidak perlu men-source script inti — cukup `export PATH="$HOME/.local/bin:$PATH"`.

## Verification (gate baseline)
```bash
make verify   # alias: make test
```
Menjalankan gate aman: `zsh -n` (parse), versi konsisten, mapping `/cmd`→fungsi utuh, smoke test command inti, dan launcher. Semua tanpa mengeksekusi command berbahaya. Status terakhir: lihat `docs/CHANGELOG.md`.

---

## ⚠️ Disclaimer
Purple-team / riset deteksi **hanya untuk lingkungan yang diizinkan** (lab sendiri, CTF, scope resmi). Penyalahgunaan melanggar hukum. Lihat `NOTICE.md`.
