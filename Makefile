# ANF Cyber Shell — Makefile verifikasi baseline
# `make verify` : jalankan gate baseline: syntax zsh + smoke test command inti
#                 (semua file output ke sandbox; tidak menyentuh repo lain).
# `make test`   : alias verify.
.PHONY: verify test

verify:
	bash scripts/verify.sh
test: verify
