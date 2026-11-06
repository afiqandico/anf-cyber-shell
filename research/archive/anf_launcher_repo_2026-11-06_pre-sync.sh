#!/usr/bin/env zsh
# ==============================================================================
# ANF — Unified Shell (Cyber + Research, merged)
# Satu perintah `anf` = shell gabungan (cyber ops + research suite).
#
#   anf                    -> shell interaktif (ZLE popup + banner)
#   anf <cmd> [args...]    -> jalankan satu command (non-interaktif)
#   anf help               -> daftar command (cyber + research)
# ==============================================================================
set -u

# --- Resolve script inti (dukung symlink + multi-lokasi) ----------------------
_SELF="${(%):-%x}"
_SELF="$(readlink -f "$_SELF" 2>/dev/null || print -r -- "$_SELF")"
_ANF_DIR="${_SELF:h}"

_ANF_LIB=""
for cand in \
    "${ANF_LIB:-}" \
    "${_ANF_DIR:h}/lib/anf/anf_cyber_shell.zsh" \
    "${_ANF_DIR:h}/lib/anf-cyber/anf_cyber_shell.zsh" \
    "${_ANF_DIR:h}/code/anf_cyber_shell.zsh" \
    "${_ANF_DIR}/../code/anf_cyber_shell.zsh" \
    "$HOME/Documents/ANF-Cyber-Shell/code/anf_cyber_shell.zsh"; do
    if [[ -n "$cand" && -f "$cand" ]]; then
        _ANF_LIB="$cand"
        break
    fi
done

if [[ -z "$_ANF_LIB" ]]; then
    print -u2 "ANF: script inti tidak ditemukan. Set ANF_LIB=<path> atau instal dengan install.sh."
    return 1 2>/dev/null || exit 1
fi

# --- Baca konfigurasi ---------------------------------------------------------
_ANF_CFG="${ANF_CONFIG:-$HOME/.config/anf-cyber/anfrc}"
[[ -f "$_ANF_CFG" ]] && source "$_ANF_CFG"

# --- Dispatch -----------------------------------------------------------------
if (( $# == 0 )); then
    if [[ -o interactive ]]; then
        return 0 2>/dev/null  # sudah ter-source di environment parent
    fi
    # Shell interaktif persisten (source lib via ZDOTDIR rc, lalu exec zsh -i).
    _anf_tmp_rc="$(mktemp -d)"
    print -r -- "source '$_ANF_LIB'" > "$_anf_tmp_rc/.zshrc"
    ZDOTDIR="$_anf_tmp_rc" exec zsh -i
    exit 0
fi

source "$_ANF_LIB"

_cmd="$1"; shift
_func="anf_${_cmd//-/_}"
if (( ${+functions[$_func]} )); then
    "$_func" "$@"
    exit $?
fi

print -u2 "ANF: command tidak dikenal: $_cmd"
print -u2 "Coba 'anf help' untuk daftar command."
exit 1