#!/usr/bin/env zsh
# ==============================================================================
# ANF — Unified Shell (Cyber + Research, merged)
# Satu perintah `anf` = shell gabungan (cyber ops + research suite).
#
#   anf                    -> shell interaktif (animasi masuk + ZLE popup + banner)
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
    # Animasi masuk (hanya TTY; tombol apa pun = lewati). Cursor disembunyikan
    # selama animasi lalu dimunculkan lagi sebelum shell start.
    if [[ -t 0 && -t 1 ]]; then
        _anf_esc=$'\e'
        _anf_C=$'\e[1;36m'   # cyan tebal
        _anf_G=$'\e[1;32m'   # hijau tebal
        _anf_Y=$'\e[1;33m'   # kuning tebal
        _anf_D=$'\e[90m'     # abu-abu
        _anf_R=$'\e[0m'
        _anf_frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
        _anf_skip=0
        printf '%s[?25l' "$_anf_esc"   # sembunyikan kursor

        # 1) Judul ketik (typewriter)
        _anf_title="ANF SHELL — Cyber + Research"
        _anf_txt=""
        for (( _c=1; _c <= ${#_anf_title}; _c++ )); do
            _anf_txt+="${_anf_title[_c]}"
            printf '\r  %s%s%s' "$_anf_C" "$_anf_txt" "$_anf_R"
            sleep 0.012
            if read -t 0.01 -k 1 _anf_key 2>/dev/null; then _anf_skip=1; break; fi
        done
        print -r -- ""

        # 2) Progress bar multi-fase dengan spinner
        if (( ! _anf_skip )); then
            _anf_phases=("modul riset" "modul cyber" "completion" "prompt & alias")
            _anf_w=26
            for (( _p=1; _p <= ${#_anf_phases}; _p++ )); do
                for (( _b=0; _b <= 8; _b++ )); do
                    _anf_t=$(( (_p - 1) * 8 + _b ))
                    _anf_pct=$(( _anf_t * 100 / 31 ))
                    _anf_fill=$(( _anf_t * _anf_w / 31 ))
                    _anf_bar=""
                    for (( _x=0; _x < _anf_w; _x++ )); do
                        if (( _x < _anf_fill )); then _anf_bar+="█"; else _anf_bar+="░"; fi
                    done
                    printf '\r  %s[%s%s%s]%s %3d%%  %s%s%s  %s%-16s%s' \
                        "$_anf_D" "$_anf_Y" "$_anf_bar" "$_anf_D" "$_anf_R" \
                        "$_anf_pct" "$_anf_G" "${_anf_frames[$(( _b % 10 + 1 ))]}" "$_anf_R" \
                        "$_anf_D" "${_anf_phases[_p]}" "$_anf_R"
                    sleep 0.035
                    if read -t 0.01 -k 1 _anf_key 2>/dev/null; then _anf_skip=1; break 2; fi
                done
            done
            print -r -- ""
            printf '  %s✓ ANF Shell siap%s — ketik %shelp%s untuk daftar command\n' \
                "$_anf_G" "$_anf_R" "$_anf_Y" "$_anf_R"
        else
            print -r -- ""
        fi
        printf '%s[?25h' "$_anf_esc"   # tampilkan kursor kembali
    fi
    ZDOTDIR="$_anf_tmp_rc" exec zsh -i
    exit 0
fi

# --- Pintu subcommand: `anf research ...` / `anf cyber ...` --------------------
# Dispatch dilakukan SEBELUM source lib: lib gabungan tidak mendefinisikan
# anf_research/anf_cyber, jadi tidak ada shadowing, dan start jadi lebih cepat.
case "${1:-}" in
    research|res) _anf_door="$HOME/.local/bin/anf-research" ;;
    cyber)        _anf_door="$HOME/.local/bin/anf-cyber" ;;
    *)            _anf_door="" ;;
esac
if [[ -n "$_anf_door" && -x "$_anf_door" ]]; then
    shift
    exec "$_anf_door" "$@"
fi

source "$_ANF_LIB"

_cmd="${1:-}"; shift
_func="anf_${_cmd//-/_}"
if (( ${+functions[$_func]} )); then
    "$_func" "$@"
    exit $?
fi

print -u2 "ANF: command tidak dikenal: $_cmd"
print -u2 "Coba 'anf help' untuk daftar command."
exit 1