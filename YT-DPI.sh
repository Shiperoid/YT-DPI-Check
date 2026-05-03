#!/bin/sh
# Bootstrap: запускаем скрипт в bash, включая окружения Entware.
if [ -z "${BASH_VERSION:-}" ]; then
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    elif [ -x /opt/bin/bash ]; then
        exec /opt/bin/bash "$0" "$@"
    elif [ -x /opt/bin/env ] && /opt/bin/env bash -c 'exit 0' >/dev/null 2>&1; then
        exec /opt/bin/env bash "$0" "$@"
    fi
    echo "Ошибка: bash не найден. Установите bash (для Entware обычно /opt/bin/bash)." >&2
    exit 1
fi

# YT-DPI.sh — интерактивный терминальный сканер доступности YouTube-доменов.
# Скрипт проверяет HTTP, TLS 1.2 и TLS 1.3, поддерживает прокси и сохраняет отчёт.
# Часть настроек хранится в ~/.config/yt-dpi/config.json (если установлен jq).
#
# PS→SH parity (v2.3.0): HTTP/TLS через curl (не C#); Deep Trace — traceroute/mtr + curl;
# обновление — один файл .sh; ресайз — SIGWINCH/stty; фон NetInfo — упрощённый опрос в главном цикле.

# Инициализация TUI: скрываем ввод/курсор и переходим в альтернативный экран.
stty -echo
printf "\033[?1049h"
printf "\033[?25l"

cleanup() {
    config_save 2>/dev/null || true
    stty echo 2>/dev/null || true
    printf "\033[?1049l"
    printf "\033[?25h"
    rm -rf "$TMP_DIR"
    exit
}

unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY

if [ -x "/usr/bin/curl" ]; then
    curl() {
        "/usr/bin/curl" "$@"
    }
fi

for cmd in curl awk; do
    if ! command -v $cmd &> /dev/null; then
        stty echo; printf "\033[?1049l"; echo "Error: $cmd is required."; exit 1
    fi
done

OS_MAC=false
if [[ "$OSTYPE" == "darwin"* ]]; then OS_MAC=true; fi

READ_TIMEOUT="0.05"
if (( BASH_VERSINFO[0] < 4 )); then READ_TIMEOUT="1"; fi

# Профиль опроса клавиш для Git Bash на Windows.
if [[ -n "${MSYSTEM:-}" ]]; then
    READ_TIMEOUT="0.03"
fi

TMP_DIR=$(mktemp -d)
E=$'\033'
trap 'cleanup' INT TERM EXIT
trap 'NEED_UI_REDRAW=true' WINCH 2>/dev/null || true

SCRIPT_VERSION="2.3.1"
SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
SCRIPT_NAME="$(basename "$SCRIPT_PATH")"
DEBUG_LOG_FILE="$SCRIPT_DIR/YT-DPI_Debug.log"
DEBUG_LOG_MAX=$((5 * 1024 * 1024))
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/yt-dpi"
CONFIG_FILE="$CONFIG_DIR/config.json"

# Блок runtime-настроек (формат совместим с bat-версией по основным полям).
export IP_PREFERENCE="IPv6"
export TLS_MODE="Auto"
HAS_IPV6=false

LAST_CHECKED_VERSION=""
RUN_COUNT=0
DEBUG_LOG_CFG=false
DEBUG_FULL_IDS_CFG=false
NEED_UI_REDRAW=false
LAST_NET_POLL_TS=0
STATUS_BAR_CACHE=""
DEBUG_SESSION_HEADER_DONE=false
YT_DPI_DEBUG_ON=0
YT_DPI_DEBUG_ID_ON=0

env_match_on() {
    local v="${1:-}"
    [[ "$v" =~ ^(1|true|yes|on)$ ]]
}

refresh_env_debug_flags() {
    env_match_on "${YT_DPI_DEBUG:-}" && YT_DPI_DEBUG_ON=1 || YT_DPI_DEBUG_ON=0
    env_match_on "${YT_DPI_DEBUG_IDENTIFIERS:-}" && YT_DPI_DEBUG_ID_ON=1 || YT_DPI_DEBUG_ID_ON=0
}
refresh_env_debug_flags

debug_enabled() {
    (( YT_DPI_DEBUG_ON )) && return 0
    [[ "$DEBUG_LOG_CFG" == true ]] || [[ "$DEBUG_LOG_CFG" == "1" ]] && return 0
    return 1
}

full_identifiers_enabled() {
    (( YT_DPI_DEBUG_ID_ON )) && return 0
    [[ "$DEBUG_FULL_IDS_CFG" == true ]] || [[ "$DEBUG_FULL_IDS_CFG" == "1" ]] && return 0
    return 1
}

debug_log_rotate_if_needed() {
    [[ -f "$DEBUG_LOG_FILE" ]] || return 0
    local sz=0
    if [[ "$OSTYPE" == "darwin"* ]]; then sz=$(stat -f%z "$DEBUG_LOG_FILE" 2>/dev/null || echo 0)
    else sz=$(stat -c%s "$DEBUG_LOG_FILE" 2>/dev/null || echo 0); fi
    (( sz < DEBUG_LOG_MAX )) && return 0
    local bak="$SCRIPT_DIR/YT-DPI_Debug_$(date '+%Y%m%d_%H%M%S').log"
    mv -f "$DEBUG_LOG_FILE" "$bak" 2>/dev/null || rm -f "$DEBUG_LOG_FILE"
}

write_debug_log() {
    debug_enabled || return 0
    debug_log_rotate_if_needed
    local lvl="${2:-DEBUG}"
    local line="[$(date '+%H:%M:%S')] [$lvl] $1"
    if command -v flock &>/dev/null; then
        (
            flock -w 8 200 || exit 0
            printf '%s\n' "$line" >> "$DEBUG_LOG_FILE"
        ) 200>>"${DEBUG_LOG_FILE}.lock"
    else
        printf '%s\n' "$line" >> "$DEBUG_LOG_FILE"
    fi
}

write_debug_session_header_once() {
    debug_enabled || return 0
    $DEBUG_SESSION_HEADER_DONE && return 0
    DEBUG_SESSION_HEADER_DONE=true
    printf '%s\n' "==================== YT-DPI SESSION START (bash) ====================" >> "$DEBUG_LOG_FILE"
    write_debug_log "Скрипт версия: $SCRIPT_VERSION" "INFO"
    write_debug_log "ОС: $(uname -srmo 2>/dev/null || uname -a)" "INFO"
    write_debug_log "Bash: $BASH_VERSION | PID: $$" "INFO"
    if full_identifiers_enabled; then
        write_debug_log "Пользователь/узел: ${USER:-?} @ $(hostname 2>/dev/null)" "INFO"
        write_debug_log "Путь к скрипту: $SCRIPT_PATH | CWD: $(pwd 2>/dev/null)" "INFO"
    else
        write_debug_log "Узел/пользователь: [обезличено] (YT_DPI_DEBUG_IDENTIFIERS=1 или пункт S5)" "INFO"
    fi
    write_debug_log "Лог-файл: $DEBUG_LOG_FILE | env debug=$YT_DPI_DEBUG_ON cfg debug=$DEBUG_LOG_CFG" "INFO"
}

PROXY_ENABLED=false
PROXY_TYPE="HTTP"
PROXY_HOST=""
PROXY_PORT=""
PROXY_USER=""
PROXY_PASS=""
PROXY_STR=""

PROXY_HISTORY=()

CDN_LIST=()
TARGETS=()

# Базовый список целей для сканирования.
BASE_TARGETS=(
    "youtu.be"
    "youtube.com"
    "i.ytimg.com"
    "s.ytimg.com"
    "yt3.ggpht.com"
    "yt4.ggpht.com"
    "s.youtube.com"
    "m.youtube.com"
    "googleapis.com"
    "tv.youtube.com"
    "googlevideo.com"
    "www.youtube.com"
    "play.google.com"
    "youtubekids.com"
    "video.google.com"
    "music.youtube.com"
    "accounts.google.com"
    "clients6.google.com"
    "studio.youtube.com"
    "manifest.googlevideo.com"
    "youtubei.googleapis.com"
    "www.youtube-nocookie.com"
    "signaler-pa.youtube.com"
    "redirector.googlevideo.com"
    "youtubeembeddedplayer.googleapis.com"
)

W_DOM=38; W_IP=22; W_HTTP=6; W_T12=8; W_T13=8; W_LAT=6; W_VER=30
X_DOM=2
X_IP=$((X_DOM + W_DOM + 1))
X_HTTP=$((X_IP + W_IP + 1))
X_T12=$((X_HTTP + W_HTTP + 1))
X_T13=$((X_T12 + W_T12 + 1))
X_LAT=$((X_T13 + W_T13 + 1))
X_VER=$((X_LAT + W_LAT + 1))
C_BLK="${E}[40m"; C_RED="${E}[31m"; C_GRN="${E}[32m"; C_YEL="${E}[33m"
C_MAG="${E}[35m"; C_CYA="${E}[36m"; C_WHT="${E}[97m"; C_GRY="${E}[90m"; C_RST="${E}[0m"

NAV_STR="[ READY ] ENTER SCAN | S SETTINGS | P PROXY | D TRACE | U UPDATE | R REPORT | H HELP | Q QUIT"
NAV_SCAN="[ BUSY ] SCANNING... Q/ESC ABORT"
NAV_ABORT="[ ABORTED ] ENTER SCAN | S P D U R H Q"
NAV_DONE="[ DONE ] ENTER SCAN | S P D U R H Q"

FRAME_BUFFER=""
# Запись строки в буфер кадра (без немедленной отправки в терминал).
out_str() {
    local x=$1 y=$2 w=$3 text=$4 color=$5
    local padded
    printf -v padded "%-${w}s" "$text"
    FRAME_BUFFER+="${E}[${y};${x}H${color}${padded}${C_RST}"
}
flush_buffer() { printf "%b" "$FRAME_BUFFER"; FRAME_BUFFER=""; }

# Нижняя строка статуса (кеш по тексту).
draw_status_bar() {
    local msg="$1"
    local pct="${2:-}"
    local bar=""
    if [[ -n "$pct" ]] && [[ "$pct" =~ ^[0-9]+$ ]] && (( pct >= 0 && pct <= 100 )); then
        local filled=$((pct / 5))
        (( filled > 20 )) && filled=20
        local i
        bar=" ["
        for (( i=0; i<20; i++ )); do
            (( i < filled )) && bar+="█" || bar+="░"
        done
        bar+="] ${pct}%"
    fi
    local key="${msg}${bar}"
    [[ "$key" == "$STATUS_BAR_CACHE" ]] && return 0
    STATUS_BAR_CACHE="$key"
    out_str 2 "$UI_Y" 121 "${msg}${bar}" "$C_WHT"
    flush_buffer
}

targets_signature() {
    local s; s=$(printf '%s\n' "${TARGETS[@]}")
    if command -v sha256sum &>/dev/null; then printf '%s' "$s" | sha256sum | awk '{print $1}'
    elif command -v shasum &>/dev/null; then printf '%s' "$s" | shasum -a 256 | awk '{print $1}'
    else printf '%s' "$s" | cksum | awk '{print $1}'; fi
}

test_internet_available() {
    local px=""
    if [[ "${PROXY_ENABLED}" == true ]] || [[ "${PROXY_ENABLED}" == "1" ]]; then px="-x $PROXY_STR"; fi
    if curl -s -m 3 $px -o /dev/null -w "%{http_code}" "https://1.1.1.1/cdn-cgi/trace" 2>/dev/null | grep -q .; then return 0; fi
    if curl -s -m 3 $px -o /dev/null "http://connectivitycheck.gstatic.com/generate_204" 2>/dev/null; then return 0; fi
    if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then return 0; fi
    if ping -n 1 -w 2 8.8.8.8 &>/dev/null; then return 0; fi
    return 1
}

flush_dns_cache() {
    if command -v resolvectl &>/dev/null; then resolvectl flush-caches 2>/dev/null && return 0; fi
    if $OS_MAC; then
        dscacheutil -flushcache 2>/dev/null
        killall -HUP mDNSResponder 2>/dev/null
        return 0
    fi
    return 1
}

version_newer() {
    awk -v cur="${1:-}" -v new="${2:-}" 'BEGIN{
      gsub(/^v/,"",cur); gsub(/^v/,"",new);
      if (length(new)==0) exit 1;
      split(cur,a,"."); split(new,b,".");
      for (i=1;i<=3;i++) {
        ai = (i in a) ? a[i]+0 : 0;
        bi = (i in b) ? b[i]+0 : 0;
        if (bi>ai) exit 0;
        if (bi<ai) exit 1;
      }
      exit 1;
    }'
}

github_latest_tag() {
    local raw tag
    raw=$(curl -s -m 12 -H "User-Agent: YT-DPI/$SCRIPT_VERSION" \
        "https://api.github.com/repos/Shiperoid/YT-DPI/releases/latest" 2>/dev/null) || return 1
    if have_jq; then
        tag=$(printf '%s' "$raw" | jq -r '.tag_name // empty' 2>/dev/null)
    else
        tag=$(printf '%s' "$raw" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' | head -n1)
    fi
    [[ -n "$tag" ]] && echo "$tag"
}

summarize_verdicts() {
    local av=0 th=0 dpi=0 ipb=0 rt=0 other=0
    local i row v
    for i in "${!TARGETS[@]}"; do
        row=$((12 + i))
        [[ -f "$TMP_DIR/$row.res" ]] || continue
        v=$(cut -d'|' -f6 < "$TMP_DIR/$row.res")
        case "$v" in
            AVAILABLE) ((av++)) ;;
            THROTTLED) ((th++)) ;;
            "DPI BLOCK") ((dpi++)) ;;
            "IP BLOCK") ((ipb++)) ;;
            "ROUTING ERROR") ((rt++)) ;;
            *) ((other++)) ;;
        esac
    done
    echo "AV=$av TH=$th DPI=$dpi IP=$ipb RT=$rt O=$other"
}

# Проверка доступности jq (нужен только для работы с JSON-конфигом).
have_jq() { command -v jq &>/dev/null; }

# Сохранение настроек в JSON-конфиг (merge с существующим файлом — не затираем чужие ключи).
config_save() {
    mkdir -p "$CONFIG_DIR" || return 1
    local hist_json
    hist_json=$(printf '%s\n' "${PROXY_HISTORY[@]}" | jq -R . 2>/dev/null | jq -s . 2>/dev/null) || hist_json='[]'
    local pe=false
    if [[ "${PROXY_ENABLED}" == true ]] || [[ "${PROXY_ENABLED}" == "1" ]]; then pe=true; fi
    local port_safe="${PROXY_PORT:-0}"
    [[ "$port_safe" =~ ^[0-9]+$ ]] || port_safe=0
    local dj=false df=false
    [[ "$DEBUG_LOG_CFG" == true ]] || [[ "$DEBUG_LOG_CFG" == "1" ]] && dj=true
    [[ "$DEBUG_FULL_IDS_CFG" == true ]] || [[ "$DEBUG_FULL_IDS_CFG" == "1" ]] && df=true
    local rc="${RUN_COUNT:-0}"
    [[ "$rc" =~ ^[0-9]+$ ]] || rc=0

    if ! have_jq; then
        write_debug_log "jq не найден — конфиг не сохранён на диск" "WARN"
        return 0
    fi

    local cur='{}'
    [[ -f "$CONFIG_FILE" ]] && cur=$(jq -c '.' "$CONFIG_FILE" 2>/dev/null) || cur='{}'

    jq -n \
        --argjson cur "$cur" \
        --arg IpPreference "$IP_PREFERENCE" \
        --arg TlsMode "$TLS_MODE" \
        --argjson ProxyEnabled "$pe" \
        --arg Type "${PROXY_TYPE:-HTTP}" \
        --arg Host "${PROXY_HOST:-}" \
        --argjson Port "$port_safe" \
        --arg User "${PROXY_USER:-}" \
        --arg Pass "${PROXY_PASS:-}" \
        --argjson History "$hist_json" \
        --arg LastCheckedVersion "${LAST_CHECKED_VERSION:-}" \
        --argjson RunCount "$rc" \
        --argjson DebugLogEnabled "$dj" \
        --argjson DebugLogFullIdentifiers "$df" \
        '$cur
            | .IpPreference = $IpPreference
            | .TlsMode = $TlsMode
            | .Proxy = {Enabled:$ProxyEnabled,Type:$Type,Host:$Host,Port:$Port,User:$User,Pass:$Pass}
            | .ProxyHistory = $History
            | .LastCheckedVersion = $LastCheckedVersion
            | .RunCount = $RunCount
            | .DebugLogEnabled = $DebugLogEnabled
            | .DebugLogFullIdentifiers = $DebugLogFullIdentifiers' \
        > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    write_debug_log "Конфиг сохранён" "INFO"
}

config_load() {
    have_jq || return 0
    [[ -f "$CONFIG_FILE" ]] || return 0
    IP_PREFERENCE=$(jq -r '.IpPreference // "IPv6"' "$CONFIG_FILE")
    TLS_MODE=$(jq -r '.TlsMode // "Auto"' "$CONFIG_FILE")
    LAST_CHECKED_VERSION=$(jq -r '.LastCheckedVersion // ""' "$CONFIG_FILE")
    RUN_COUNT=$(jq -r '.RunCount // 0' "$CONFIG_FILE")
    [[ "$RUN_COUNT" =~ ^[0-9]+$ ]] || RUN_COUNT=0
    DEBUG_LOG_CFG=$(jq -r '.DebugLogEnabled // false' "$CONFIG_FILE")
    DEBUG_FULL_IDS_CFG=$(jq -r '.DebugLogFullIdentifiers // false' "$CONFIG_FILE")

    PROXY_HISTORY=()
    local line
    while IFS= read -r line; do
        [[ -n "$line" ]] && PROXY_HISTORY+=("$line")
    done < <(jq -r '.ProxyHistory[]? // empty' "$CONFIG_FILE" 2>/dev/null)

    local en type host port user pass
    en=$(jq -r '.Proxy.Enabled // false' "$CONFIG_FILE")
    type=$(jq -r '.Proxy.Type // "HTTP"' "$CONFIG_FILE")
    host=$(jq -r '.Proxy.Host // ""' "$CONFIG_FILE")
    port=$(jq -r '.Proxy.Port // 0' "$CONFIG_FILE")
    user=$(jq -r '.Proxy.User // ""' "$CONFIG_FILE")
    pass=$(jq -r '.Proxy.Pass // ""' "$CONFIG_FILE")

    PROXY_ENABLED=false
    PROXY_TYPE="HTTP"; PROXY_HOST=""; PROXY_PORT=""; PROXY_USER=""; PROXY_PASS=""; PROXY_STR=""
    if [[ "$en" == "true" ]] && [[ -n "$host" ]] && [[ "$port" =~ ^[0-9]+$ ]] && (( port > 0 )); then
        PROXY_ENABLED=true
        PROXY_TYPE=$(echo "$type" | tr 'a-z' 'A-Z')
        PROXY_HOST="$host"
        PROXY_PORT="$port"
        PROXY_USER="$user"
        PROXY_PASS="$pass"
        local t_lower userpass_str=""
        t_lower=$(echo "$PROXY_TYPE" | tr 'A-Z' 'a-z')
        if [[ -n "$PROXY_USER" && -n "$PROXY_PASS" ]]; then userpass_str="${PROXY_USER}:${PROXY_PASS}@"; fi
        PROXY_STR="${t_lower}://${userpass_str}${PROXY_HOST}:${PROXY_PORT}"
        if [[ "${PROXY_TYPE}" == "SOCKS5" ]]; then PROXY_STR="${PROXY_STR/socks5:\/\//socks5h:\/\/}"; fi
    fi
    refresh_env_debug_flags
}

detect_ipv6() {
    HAS_IPV6=false
    local has_route=false

    # Шаг 1: проверяем, что у системы есть default IPv6 route.
    if command -v ip &>/dev/null; then
        if ip -6 route show default 2>/dev/null | awk 'NF { found=1 } END { exit(found?0:1) }'; then
            has_route=true
        fi
    elif $OS_MAC; then
        if netstat -rn -f inet6 2>/dev/null | awk '$1=="default" || $1=="::/0" { found=1 } END { exit(found?0:1) }'; then
            has_route=true
        fi
    elif command -v route &>/dev/null; then
        if route -n -A inet6 2>/dev/null | awk '$1=="::/0" || $1=="default" { found=1 } END { exit(found?0:1) }'; then
            has_route=true
        fi
    fi

    if ! $has_route; then
        return
    fi

    # Шаг 2: проверяем исходящую IPv6-связность.
    if curl -6 -s -m 2 -I "https://ipv6.google.com" -o /dev/null 2>/dev/null; then
        HAS_IPV6=true
        return
    fi
    if command -v ping6 &>/dev/null; then
        if ping6 -c 1 -W 1 2001:4860:4860::8888 &>/dev/null; then
            HAS_IPV6=true
            return
        fi
    fi
}

# Формирование итогового списка целей: base + CDN, без дублей, сортировка по длине.
rebuild_targets() {
    local -a raw=()
    local x
    for x in "${BASE_TARGETS[@]}"; do raw+=("$x"); done
    for x in "${CDN_LIST[@]}"; do raw+=("$x"); done
    [[ -n "${CDN:-}" ]] && raw+=("$CDN")
    mapfile -t TARGETS < <(printf '%s\n' "${raw[@]}" | awk '!seen[$0]++' | awk '{ print length"\t"$0 }' | sort -n | cut -f2-)
}

proxy_history_add() {
    local entry=""
    if [[ "${PROXY_ENABLED}" != true ]] && [[ "${PROXY_ENABLED}" != "1" ]]; then return 0; fi
    entry="${PROXY_TYPE}://"
    if [[ -n "$PROXY_USER" ]]; then entry+="$PROXY_USER:*****@"; fi
    entry+="$PROXY_HOST:$PROXY_PORT"
    local i new_hist=()
    new_hist+=("$entry")
    for (( i=0; i<${#PROXY_HISTORY[@]}; i++ )); do
        [[ "${PROXY_HISTORY[$i]}" == "$entry" ]] && continue
        new_hist+=("${PROXY_HISTORY[$i]}")
        (( ${#new_hist[@]} >= 5 )) && break
    done
    PROXY_HISTORY=("${new_hist[@]}")
    config_save
}

# Получение сетевого контекста для верхней панели: DNS, CDN, ISP/LOC, наличие IPv6.
get_network_info() {
    DNS=$(grep nameserver /etc/resolv.conf 2>/dev/null | head -n 1 | awk '{print $2}' | tr -d '\r\n')
    [ -z "$DNS" ] && DNS="UNKNOWN"

    local px_args=""
    if [[ "${PROXY_ENABLED}" == true ]] || [[ "${PROXY_ENABLED}" == "1" ]]; then px_args="-x $PROXY_STR"; fi

    CDN_LIST=()
    local cdn_prefixes=( r1 r2 r3 rr1 rr2 rr3 rr4 rr5 )
    local pfx host
    for pfx in "${cdn_prefixes[@]}"; do
        host="${pfx}.googlevideo.com"
        if command -v getent &>/dev/null; then
            if getent ahostsv4 "$host" &>/dev/null; then CDN_LIST+=("$host"); fi
        elif command -v nslookup &>/dev/null; then
            if nslookup "$host" &>/dev/null; then CDN_LIST+=("$host"); fi
        fi
    done

    if [ ${#CDN_LIST[@]} -eq 0 ]; then
        local rnd=$RANDOM
        local cdn_raw=$(curl -s -m 2 $px_args "http://redirector.googlevideo.com/report_mapping?di=no&nocache=$rnd")
        if [[ "$cdn_raw" =~ =\>\ ([a-zA-Z0-9-]+) ]]; then
            CDN_LIST+=("r1.${BASH_REMATCH[1]}.googlevideo.com")
        else
            CDN_LIST+=("manifest.googlevideo.com")
        fi
    fi

    CDN="${CDN_LIST[0]}"

    ISP="UNKNOWN"; LOC="UNKNOWN"
    local geo_raw=$(curl -s -A "curl/7.88.1" -m 2 $px_args "http://ip-api.com/line/?fields=status,countryCode,city,isp")
    if [ "$(echo "$geo_raw" | sed -n '1p' | tr -d '\r\n')" == "success" ]; then
        LOC="$(echo "$geo_raw" | sed -n '3p' | tr -d '\r\n'), $(echo "$geo_raw" | sed -n '2p' | tr -d '\r\n')"
        ISP=$(echo "$geo_raw" | sed -n '4p' | tr -d '\r\n' | sed -E 's/ (LLC|Inc\.?|Ltd\.?|sp\. z o\.o\.|CJSC|OJSC|PJSC|PAO|ZAO|OOO|JSC)//g')
        [ ${#ISP} -gt 25 ] && ISP="${ISP:0:22}..."
    fi

    detect_ipv6
}

draw_ui() {
    clear; FRAME_BUFFER=""
    out_str 1 1 0 ' ██╗   ██╗████████╗    ██████╗ ██████╗ ██╗' "$C_GRN"
    out_str 1 2 0 ' ╚██╗ ██╔╝╚══██╔══╝    ██╔══██╗██╔══██╗██║' "$C_GRN"
    out_str 1 3 0 '  ╚████╔╝    ██║ █████╗██║  ██║██████╔╝██║' "$C_GRN"
    out_str 1 4 0 '   ╚██╔╝     ██║ ╚════╝██║  ██║██╔═══╝ ██║' "$C_GRN"
    out_str 1 5 0 '    ██║      ██║       ██████║ ██║     ██║' "$C_GRN"
    out_str 1 6 0 '    ╚═╝      ╚═╝       ╚═════╝ ╚═╝     ╚═╝' "$C_GRN"

    out_str 45 1 0 '██████╗    ██████╗ ' "$C_GRY"
    out_str 45 2 0 '╚════██╗   ╚════██╗' "$C_GRY"
    out_str 45 3 0 ' █████╔╝    █████╔╝' "$C_GRY"
    out_str 45 4 0 '██╔═══╝    ██╔═══╝' "$C_GRY"
    out_str 45 5 0 '███████╗██╗███████╗' "$C_GRY"
    out_str 45 6 0 '╚══════╝╚═╝╚══════╝' "$C_GRY"

    out_str 65 1 0 "> SYS STATUS: [ ONLINE ]" "$C_GRN"
    out_str 65 2 50 "> ENGINE: Barebuh Pro v2.3.4" "$C_RED"
    out_str 65 3 50 "> LOCAL DNS: $DNS" "$C_CYA"
    out_str 65 4 50 "> CDN NODE: $CDN" "$C_YEL"
    out_str 65 5 0 "> AUTHOR: github.com/Shiperoid" "$C_GRN"

    local disp_isp="$ISP" disp_loc="$LOC"
    ((${#disp_isp} > 35)) && disp_isp="${disp_isp:0:32}..."
    ((${#disp_loc} > 30)) && disp_loc="${disp_loc:0:27}..."
    local isp_str="> ISP / LOC: $disp_isp ($disp_loc)"
    local isp_pad="${isp_str}"
    ((${#isp_pad} < 80)) && isp_pad=$(printf '%-80s' "$isp_str") || isp_pad="${isp_str:0:80}"
    out_str 65 6 80 "$isp_pad" "$C_MAG"

    local px_stat
    if [[ "${PROXY_ENABLED}" == true ]] || [[ "${PROXY_ENABLED}" == "1" ]]; then
        px_stat="> PROXY: $PROXY_TYPE $PROXY_HOST:$PROXY_PORT Connected"
    else
        px_stat="> PROXY: [ OFF ]"
    fi
    local px_pad="$px_stat"
    ((${#px_pad} < 58)) && px_pad=$(printf '%-58s' "$px_stat") || px_pad="${px_stat:0:58}"
    out_str 65 7 58 "$px_pad" "$C_YEL"

    out_str 65 8 0 "> TG: t.me/YT_DPI | VERSION: $SCRIPT_VERSION" "$C_GRN"

    local l="========================================================================================================================="
    out_str 0 9 0 "$l" "$C_CYA"
    out_str $X_DOM 10 0 "TARGET DOMAIN" "$C_WHT"
    out_str $X_IP  10 0 "IP ADDRESS" "$C_WHT"
    out_str $X_HTTP 10 0 "HTTP" "$C_WHT"
    out_str $X_T12 10 0 "TLS 1.2" "$C_WHT"
    out_str $X_T13 10 0 "TLS 1.3" "$C_WHT"
    out_str $X_LAT 10 0 "LAT" "$C_WHT"
    out_str $X_VER 10 0 "RESULT" "$C_WHT"
    out_str 0 11 0 "$l" "$C_CYA"

    for i in "${!TARGETS[@]}"; do
        local row=$((12 + i))
        out_str $X_DOM $row $W_DOM "${TARGETS[$i]}" "$C_GRY"
        out_str $X_IP   $row $W_IP "---.---.---.---" "$C_GRY"
        out_str $X_HTTP $row $W_HTTP "--" "$C_GRY"
        out_str $X_T12  $row $W_T12 "--" "$C_GRY"
        out_str $X_T13  $row $W_T13 "--" "$C_GRY"
        out_str $X_LAT  $row $W_LAT "----" "$C_GRY"
        out_str $X_VER  $row $W_VER "IDLE" "$C_GRY"
    done
    out_str 0 $((12 + ${#TARGETS[@]})) 0 "$l" "$C_CYA"
    flush_buffer
}

show_help_menu() {
    local page=0
    local total=5
    while true; do
        stty echo
        clear
        echo -e "${C_CYA}── YT-DPI v${SCRIPT_VERSION} — справка (стр. $((page + 1))/${total}) ──${C_RST}\n"
        case $page in
            0)
                echo -e "${C_WHT}[ ЧТО ДЕЛАЕТ ]${C_RST}"
                echo -e "  Параллельно проверяет домены: HTTP:80, TLS 1.2 и 1.3 на 443 (SNI). Диагностика DPI/ТСПУ."
                echo -e "\n${C_WHT}[ ГОРЯЧИЕ КЛАВИШИ ]${C_RST}"
                echo -e "  ${C_YEL}ENTER${C_RST} — скан таблицы | ${C_YEL}S${C_RST} настройки | ${C_YEL}P${C_RST} прокси"
                echo -e "  ${C_YEL}D${C_RST} Deep Trace | ${C_YEL}U${C_RST} обновление с GitHub | ${C_YEL}R${C_RST} отчёт"
                echo -e "  ${C_YEL}H${C_RST} справка | ${C_YEL}Q / ESC${C_RST} выход"
                ;;
            1)
                echo -e "${C_WHT}[ КОЛОНКИ ]${C_RST} №/TARGET, IP, HTTP, T12, T13, LAT, RESULT."
                echo -e "\n${C_WHT}[ КОДЫ ЯЧЕЕК ]${C_RST}"
                echo -e "  ${C_GRN}OK${C_RST} OK | ${C_RED}ERR/RST/DRP${C_RST} см. README PS | ${C_GRY}N/A ---${C_RST}"
                ;;
            2)
                echo -e "${C_WHT}[ ВЕРДИКТЫ ]${C_RST} AVAILABLE, THROTTLED, DPI BLOCK, IP BLOCK, ROUTING ERROR."
                echo -e "  Сначала смотрите HTTP, затем TLS."
                ;;
            3)
                echo -e "${C_WHT}[ DEEP TRACE (D) ]${C_RST}"
                echo -e "  Номер строки 1…N; в sh используются traceroute/mtr и curl к :443 (не C#)."
                ;;
            4)
                echo -e "${C_WHT}[ ПРОКСИ P ]${C_RST} 1 тест 2 выкл 3 очистить историю 4 новый адрес; 5+ история; 0/Esc назад."
                echo -e "${C_WHT}[ S ]${C_RST} 1 IP pref 2 сброс DNS-кэша (где есть) 3 TLS цикл 4 лог 5 полные ID в логе."
                echo -e "${C_WHT}[ U ]${C_RST} сверка релиза GitHub, загрузка ${C_CYA}YT-DPI.sh${C_RST}."
                echo -e "${C_WHT}[ TLS ]${C_RST} chrome://flags/#enable-tls13-kyber — при нестабильности Kyber."
                ;;
        esac
        echo -e "\n${C_GRY}N/→ далее  P/← назад  Enter/Esc/другая — закрыть${C_RST}"
        read -rsn1 k || true
        [[ "$k" == $'\e' ]] && read -rsn2 k2 2>/dev/null || k2=""
        if [[ "$k" == $'\n' || "$k" == $'\r' ]] || [[ "$k$k2" == $'\e[A' ]] || [[ "$k$k2" == $'\e[D' ]] || [[ "$k" == "p" || "$k" == "P" || "$k" == "з" || "$k" == "З" ]]; then
            page=$(( (page - 1 + total) % total ))
            continue
        fi
        if [[ "$k" == "n" || "$k" == "N" || "$k" == "т" || "$k" == "Т" ]] || [[ "$k$k2" == $'\e[B' ]] || [[ "$k$k2" == $'\e[C' ]]; then
            page=$(( (page + 1) % total ))
            continue
        fi
        break
    done
    stty -echo
}

# Меню настроек (паритет PS [S]).
show_settings_menu() {
    while true; do
        stty echo
        clear
        echo -e "${C_CYA}=== SETTINGS / НАСТРОЙКИ ===${C_RST}\n"
        echo -e "  1. Протокол IP: ${C_YEL}$IP_PREFERENCE${C_RST} (переключить IPv6 pref ↔ только IPv4)"
        echo -e "  2. Сброс сетевого кэша (DNS resolver где доступно)"
        echo -e "  3. Режим TLS: ${C_YEL}$TLS_MODE${C_RST} (цикл Auto → TLS12 → TLS13)"
        local dsl="ВЫКЛ"; [[ "$DEBUG_LOG_CFG" == true ]] || [[ "$DEBUG_LOG_CFG" == "1" ]] && dsl="ВКЛ"
        local dsf="ВЫКЛ"; [[ "$DEBUG_FULL_IDS_CFG" == true ]] || [[ "$DEBUG_FULL_IDS_CFG" == "1" ]] && dsf="ВКЛ"
        echo -e "  4. Отладочный лог: ${C_YEL}$dsl${C_RST} ($DEBUG_LOG_FILE)"
        echo -e "  5. Полные ID в заголовке лога: ${C_YEL}$dsf${C_RST}"
        echo -e "  ${C_GRY}0 / Enter — назад${C_RST}"
        echo -ne "\n${C_YEL}> ${C_RST}"
        local c
        read -r c
        stty -echo
        case "$c" in
            1)
                if [[ "$IP_PREFERENCE" == "IPv6" ]]; then IP_PREFERENCE="IPv4"; else IP_PREFERENCE="IPv6"; fi
                config_save; write_debug_session_header_once
                ;;
            2)
                if flush_dns_cache; then echo -e "${C_GRN}[OK] DNS cache flush попытка выполнена.${C_RST}"
                else echo -e "${C_YEL}[i] Авто-сброс DNS недоступен на этой ОС — пропустите или сбросьте вручную.${C_RST}"; fi
                ISP="UNKNOWN"; LOC="UNKNOWN"
                sleep 1
                ;;
            3)
                case "$TLS_MODE" in
                    Auto) TLS_MODE="TLS12" ;;
                    TLS12) TLS_MODE="TLS13" ;;
                    *) TLS_MODE="Auto" ;;
                esac
                config_save
                ;;
            4)
                if [[ "$DEBUG_LOG_CFG" == true ]] || [[ "$DEBUG_LOG_CFG" == "1" ]]; then DEBUG_LOG_CFG=false; else DEBUG_LOG_CFG=true; fi
                config_save
                DEBUG_SESSION_HEADER_DONE=false
                write_debug_session_header_once
                ;;
            5)
                if [[ "$DEBUG_FULL_IDS_CFG" == true ]] || [[ "$DEBUG_FULL_IDS_CFG" == "1" ]]; then DEBUG_FULL_IDS_CFG=false; else DEBUG_FULL_IDS_CFG=true; fi
                config_save
                DEBUG_SESSION_HEADER_DONE=false
                write_debug_session_header_once
                ;;
            0|""|$'\r') break ;;
        esac
    done
}

# Применение записи из истории прокси.
# Формат записи: TYPE://[user:*****@]host:port
apply_proxy_history_entry() {
    local entry=$1
    [[ -z "$entry" ]] && return 1
    local proto="" user="" host="" port=""
    if [[ "$entry" =~ ^([a-zA-Z]+)://(?:([^:]+):\*\*\*\*\*@)?([^:]+):([0-9]+)$ ]]; then
        proto="${BASH_REMATCH[1]}"
        user="${BASH_REMATCH[2]}"
        host="${BASH_REMATCH[3]}"
        port="${BASH_REMATCH[4]}"
    else
        return 1
    fi
    PROXY_TYPE=$(echo "$proto" | tr 'a-z' 'A-Z')
    PROXY_HOST="$host"
    PROXY_PORT="$port"
    PROXY_USER="${user:-}"
    PROXY_PASS=""
    if [[ -n "$PROXY_USER" ]]; then
        stty echo
        echo -ne "\n${C_YEL}Пароль для $PROXY_USER@${PROXY_HOST}:${PROXY_PORT}: ${C_RST}"
        read -r PROXY_PASS
        stty -echo
    fi
    local userpass_str="" t_lower
    if [[ -n "$PROXY_USER" && -n "$PROXY_PASS" ]]; then userpass_str="${PROXY_USER}:${PROXY_PASS}@"; fi
    t_lower=$(echo "$PROXY_TYPE" | tr 'A-Z' 'a-z')
    PROXY_STR="${t_lower}://${userpass_str}${PROXY_HOST}:${PROXY_PORT}"
    PROXY_ENABLED=true
    if [[ "$PROXY_TYPE" == "SOCKS5" ]]; then PROXY_STR="${PROXY_STR/socks5:\/\//socks5h:\/\/}"; fi
    return 0
}

SNAP_PE=false SNAP_PT="" SNAP_PH="" SNAP_PP="" SNAP_PU="" SNAP_PPASS="" SNAP_PSTR=""

proxy_snapshot_save() {
    SNAP_PE=$PROXY_ENABLED
    SNAP_PT=$PROXY_TYPE
    SNAP_PH=$PROXY_HOST
    SNAP_PP=$PROXY_PORT
    SNAP_PU=$PROXY_USER
    SNAP_PPASS=$PROXY_PASS
    SNAP_PSTR=$PROXY_STR
}

proxy_snapshot_restore() {
    PROXY_ENABLED=$SNAP_PE
    PROXY_TYPE=$SNAP_PT
    PROXY_HOST=$SNAP_PH
    PROXY_PORT=$SNAP_PP
    PROXY_USER=$SNAP_PU
    PROXY_PASS=$SNAP_PPASS
    PROXY_STR=$SNAP_PSTR
}

proxy_ping_google_ms() {
    local ms ec
    ms=$(curl -s -m 6 -x "$PROXY_STR" -o /dev/null -w "%{time_connect}" -I "http://google.com" 2>/dev/null)
    ec=$?
    (( ec != 0 )) && return 1
    echo "$(awk -v m="$ms" 'BEGIN{ printf "%d", int(m*1000+0.5) }')"
}

apply_manual_proxy_and_verify() {
    local px_input=$1
    local re="^((http|https|socks5)://)?(([^:]+):([^@]+)@)?([^:/]+|\[[a-fA-F0-9:]+\]):([0-9]{1,5})$"
    shopt -s nocasematch
    if ! [[ "$px_input" =~ $re ]]; then
        shopt -u nocasematch
        echo -e "${C_RED}[FAIL] Неверный формат.${C_RST}"; sleep 2
        return 1
    fi
    shopt -u nocasematch
    local t="${BASH_REMATCH[2]}" u="${BASH_REMATCH[4]}" pw="${BASH_REMATCH[5]}"
    local h="${BASH_REMATCH[6]}" p="${BASH_REMATCH[7]}"
    if (( p <= 0 || p > 65535 )); then echo -e "${C_RED}[FAIL] Порт.${C_RST}"; sleep 2; return 1; fi
    local userpass_str=""
    if [[ -n "$u" && -n "$pw" ]]; then userpass_str="${u}:${pw}@"; fi
    if [[ -z "$t" ]]; then
        echo -e "${C_GRY}[*] Определение типа прокси...${C_RST}"
        if curl -s -m 4 -x "socks5://${userpass_str}${h}:${p}" -I "http://google.com" -o /dev/null 2>/dev/null; then t="socks5"
        elif curl -s -m 4 -x "http://${userpass_str}${h}:${p}" -I "http://google.com" -o /dev/null 2>/dev/null; then t="http"
        else
            echo -e "${C_RED}[FAIL] Укажите явно socks5:// или http://${C_RST}"; sleep 2; return 1
        fi
    fi
    proxy_snapshot_save
    PROXY_ENABLED=true
    PROXY_TYPE=$(echo "$t" | tr 'a-z' 'A-Z')
    PROXY_HOST="$h"; PROXY_PORT="$p"; PROXY_USER="${u:-}"; PROXY_PASS="${pw:-}"
    local t_lower=$(echo "$PROXY_TYPE" | tr 'A-Z' 'a-z')
    PROXY_STR="${t_lower}://${userpass_str}${PROXY_HOST}:${PROXY_PORT}"
    if [[ "$PROXY_TYPE" == "SOCKS5" ]]; then PROXY_STR="${PROXY_STR/socks5:\/\//socks5h:\/\/}"; fi
    local ms
    ms=$(proxy_ping_google_ms) || {
        proxy_snapshot_restore
        echo -e "${C_RED}[FAIL] Прокси не отвечает. Настройки восстановлены.${C_RST}"; sleep 2
        return 1
    }
    echo -e "${C_GRN}[OK] Прокси OK (~${ms} мс).${C_RST}"
    proxy_history_add
    config_save
    sleep 1
    return 0
}

# Меню прокси как в PS (цифры).
show_proxy_menu() {
    local hist_base=5
    while true; do
        stty echo
        clear
        echo -e "${C_CYA}=== НАСТРОЙКА ПРОКСИ ===${C_RST}\n"
        if [[ "${PROXY_ENABLED}" == true ]] || [[ "${PROXY_ENABLED}" == "1" ]]; then
            echo -e "  ТЕКУЩИЙ: ${C_GRN}$PROXY_TYPE://${PROXY_HOST}:$PROXY_PORT${C_RST}"
        else
            echo -e "  ТЕКУЩИЙ: ${C_GRY}ОТКЛЮЧЕН${C_RST}"
        fi
        echo -e "\n  ${C_WHT}Действия:${C_RST}"
        echo -e "    1 — проверить текущий прокси"
        echo -e "    2 — выключить прокси"
        echo -e "    3 — очистить историю (Y/N)"
        echo -e "    4 — ввести новый адрес"
        if ((${#PROXY_HISTORY[@]} > 0)); then
            echo -e "\n  ${C_WHT}Из истории:${C_RST}"
            local hi
            for (( hi=0; hi<${#PROXY_HISTORY[@]}; hi++ )); do
                echo -e "    $((hist_base + hi)) — ${PROXY_HISTORY[$hi]}"
            done
        fi
        echo -e "\n  ${C_GRY}0 или Esc — назад${C_RST}"
        echo -ne "\n${C_YEL}Цифра: ${C_RST}"
        local dig
        read -rsn1 dig || true
        stty -echo
        [[ "$dig" == $'\e' || "$dig" == "0" ]] && break
        case "$dig" in
            1)
                test_proxy_connection
                ;;
            2)
                PROXY_ENABLED=false
                PROXY_TYPE="HTTP"; PROXY_HOST=""; PROXY_PORT=""; PROXY_USER=""; PROXY_PASS=""; PROXY_STR=""
                config_save
                echo -e "${C_GRN}[OK] Прокси выключен.${C_RST}"; sleep 1
                ;;
            3)
                if ((${#PROXY_HISTORY[@]} == 0)); then echo -e "${C_YEL}История пуста.${C_RST}"; sleep 1; continue; fi
                stty echo
                echo -ne "${C_YEL}Очистить историю? Y/N: ${C_RST}"
                local yn
                read -rn1 yn
                echo
                stty -echo
                if [[ "$yn" == "y" || "$yn" == "Y" ]]; then
                    PROXY_HISTORY=()
                    config_save
                    echo -e "${C_GRN}[OK] Очищено.${C_RST}"; sleep 1
                fi
                ;;
            4)
                stty echo
                echo -ne "${C_YEL}Прокси (пустой Enter — отмена): ${C_RST}"
                local line
                read -r line
                stty -echo
                line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                [[ -z "$line" ]] && continue
                apply_manual_proxy_and_verify "$line"
                ;;
            [5-9])
                local idx=$((dig - hist_base))
                if (( idx >= 0 && idx < ${#PROXY_HISTORY[@]} )); then
                    proxy_snapshot_save
                    if apply_proxy_history_entry "${PROXY_HISTORY[$idx]}"; then
                        local ms
                        ms=$(proxy_ping_google_ms) || {
                            proxy_snapshot_restore
                            echo -e "${C_RED}[FAIL] Запись истории не работает.${C_RST}"; sleep 2
                            continue
                        }
                        echo -e "${C_GRN}[OK] Из истории (~${ms} мс).${C_RST}"
                        proxy_history_add
                        config_save
                        sleep 1
                    fi
                else
                    echo -e "${C_YEL}Нет такого пункта.${C_RST}"; sleep 1
                fi
                ;;
            *)
                ;;
        esac
    done
}

# Полный тест прокси (пункт P→1 или бывший T).
test_proxy_connection() {
    stty echo
    clear
    echo -e "${C_CYA}=== ТЕСТ ПРОКСИ ===${C_RST}"
    if [[ "${PROXY_ENABLED}" != true ]] && [[ "${PROXY_ENABLED}" != "1" ]]; then
        echo -e "${C_RED}Прокси отключён.${C_RST}"; sleep 2; stty -echo; return
    fi
    echo -e "${C_YEL}google.com через $PROXY_TYPE...${C_RST}"
    local ms
    ms=$(proxy_ping_google_ms) && echo -e "${C_GRN}OK, connect ~ ${ms} мс${C_RST}" || echo -e "${C_RED}Ошибка.${C_RST}"
    echo -ne "\n${C_CYA}Клавиша...${C_RST}"; read -rn1 -s; echo
    stty -echo
}

# Совместимость: старый вызов test_proxy → меню или быстрый тест.
test_proxy() { test_proxy_connection; }

# Резолв адреса цели с учётом IP preference и доступности IPv6.
resolve_target_ip() {
    local target=$1
    local ip=""

    if [[ "${PROXY_ENABLED}" == true ]] || [[ "${PROXY_ENABLED}" == "1" ]]; then
        echo "[ *PROXIED* ]"
        return 0
    fi

    if [[ "$IP_PREFERENCE" == "IPv6" ]] && $HAS_IPV6 && command -v getent &>/dev/null; then
        ip=$(getent ahostsv6 "$target" 2>/dev/null | awk '/STREAM|STREAM tcp/ {print $1; exit}')
        [[ -z "$ip" ]] && ip=$(getent ahostsv6 "$target" 2>/dev/null | awk '{print $1; exit}')
        if [[ -n "$ip" ]]; then echo "$ip"; return 0; fi
    fi

    if command -v getent &>/dev/null; then
        ip=$(getent ahostsv4 "$target" 2>/dev/null | awk '{print $1}' | head -n 1)
    fi
    if [ -z "$ip" ] && command -v nslookup &>/dev/null; then
        ip=$(nslookup "$target" 2>/dev/null | awk '/^Address: / {print $2}' | grep -v ':' | head -n 1)
    fi
    if [ -z "$ip" ]; then
        if $OS_MAC; then ip=$(LC_ALL=C ping -c 1 -t 1 "$target" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
        else ip=$(LC_ALL=C ping -c 1 -W 1 "$target" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1); fi
    fi

    if [ -z "$ip" ]; then echo ""; return 1; fi
    echo "$ip"
    return 0
}

# Рабочий поток проверки одной цели.
# Формат результата: IP|HTTP|TLS12|TLS13|LAT|VERDICT|COLOR
worker() {
    local target=$1 row=$2
    local ip="" http="FAIL" t12="FAIL" t13="FAIL" lat="0ms" verdict="IP BLOCK" color="$C_RED"

    local px_args=""
    if [[ "${PROXY_ENABLED}" == true ]] || [[ "${PROXY_ENABLED}" == "1" ]]; then
        px_args="-x $PROXY_STR"
        if [[ "$PROXY_TYPE" == "SOCKS5" ]]; then px_args="${px_args/socks5:\/\//socks5h:\/\/}"; fi
        ip="[ *PROXIED* ]"
    else
        ip=$(resolve_target_ip "$target") || true
        if [ -z "$ip" ]; then echo "ERROR|FAIL|FAIL|FAIL|0ms|DNS ERROR|$C_RED" > "$TMP_DIR/$row.res"; return; fi
    fi

    local http_out lat_raw
    http_out=$(curl -s -m 2 $px_args -I "http://$target" -A "curl/7.88.1" -w "\nTIME_TOTAL=%{time_total}" 2>&1)
    if [ $? -eq 0 ]; then
        http="OK"
        lat_raw=$(echo "$http_out" | tr ',' '.' | awk -F= '/^TIME_TOTAL=/{print $2}' | tail -n1 | tr -d '\r')
        if [[ "$lat_raw" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
            lat=$(awk -v t="$lat_raw" 'BEGIN{v=int(t*1000); if(v<1) v=1; print v"ms"}')
        else
            lat="---"
        fi
    else
        if echo "$http_out" | grep -qi "timeout"; then http="DROP"; else http="ERR"; fi
    fi

    if [[ "$TLS_MODE" == "TLS13" ]]; then
        t12="---"
    else
        local t12_out
        t12_out=$(curl -k -s -m 3 $px_args -I "https://$target" --tls-max 1.2 2>&1)
        if [ $? -eq 0 ]; then t12="OK"
        elif echo "$t12_out" | grep -qi "reset"; then t12="RST"
        else t12="DRP"
        fi
    fi

    if [[ "$TLS_MODE" == "TLS12" ]]; then
        t13="---"
    else
        local t13_out
        t13_out=$(LC_ALL=C curl -k -s -m 3 $px_args -I "https://$target" --tlsv1.3 2>&1)
        if [ $? -eq 0 ]; then t13="OK"
        elif echo "$t13_out" | grep -qiE "unsupported|not supported|unknown option|unrecognized option|built-in"; then t13="N/A"
        elif echo "$t13_out" | grep -qi "reset"; then t13="RST"
        else t13="DRP"
        fi
    fi

    if [ "$http" == "OK" ]; then
        if [[ "$TLS_MODE" == "TLS12" ]]; then
            if [ "$t12" == "OK" ]; then verdict="AVAILABLE"; color="$C_GRN"
            elif [ "$t12" == "RST" ] || [ "$t12" == "DRP" ]; then verdict="DPI BLOCK"; color="$C_YEL"
            else verdict="DPI BLOCK"; color="$C_YEL"; fi
        elif [[ "$TLS_MODE" == "TLS13" ]]; then
            if [ "$t13" == "OK" ]; then verdict="AVAILABLE"; color="$C_GRN"
            elif [ "$t13" == "N/A" ]; then verdict="AVAILABLE"; color="$C_GRN"
            elif [ "$t13" == "RST" ] || [ "$t13" == "DRP" ]; then verdict="DPI BLOCK"; color="$C_YEL"
            else verdict="DPI BLOCK"; color="$C_YEL"; fi
        else
            if [ "$t12" == "OK" ] && [ "$t13" == "OK" ]; then verdict="AVAILABLE"; color="$C_GRN"
            elif [ "$t12" == "OK" ] && [ "$t13" == "N/A" ]; then verdict="AVAILABLE"; color="$C_GRN"
            elif [ "$t12" == "N/A" ] && [ "$t13" == "OK" ]; then verdict="AVAILABLE"; color="$C_GRN"
            elif [ "$t12" == "OK" ] && { [ "$t13" == "RST" ] || [ "$t13" == "DRP" ]; }; then verdict="THROTTLED"; color="$C_YEL"
            elif [ "$t13" == "OK" ] && { [ "$t12" == "RST" ] || [ "$t12" == "DRP" ]; }; then verdict="THROTTLED"; color="$C_YEL"
            else verdict="DPI BLOCK"; color="$C_YEL"; fi
        fi
    else
        # HTTP не OK -> смотрим RST ошибки
        if { [ "$t12" == "RST" ] || [ "$t13" == "RST" ]; } && [ "$http" == "ERR" ]; then
            verdict="ROUTING ERROR"; color="$C_RED"
        else
            verdict="IP BLOCK"; color="$C_RED"
        fi
    fi

    echo "$ip|$http|$t12|$t13|$lat|$verdict|$color" > "$TMP_DIR/$row.res"
}

paint_result_row() {
    local row=$1
    [[ -f "$TMP_DIR/$row.res" ]] || return 0
    local ip http t12 t13 lat verdict color
    IFS='|' read -r ip http t12 t13 lat verdict color < "$TMP_DIR/$row.res"
    out_str $X_IP   $row $W_IP "$ip" "$C_GRY"
    local hcol=$C_RED
    [ "$http" == "OK" ] && hcol="$C_GRN"
    out_str $X_HTTP $row $W_HTTP "$http" "$hcol"
    local t12col=$C_RED
    [ "$t12" == "OK" ] && t12col="$C_GRN"
    [[ "$t12" == "---" ]] && t12col="$C_GRY"
    out_str $X_T12  $row $W_T12 "$t12" "$t12col"
    local t13col=$C_RED
    if [ "$t13" == "OK" ]; then t13col="$C_GRN"
    elif [ "$t13" == "N/A" ] || [ "$t13" == "---" ]; then t13col="$C_GRY"; fi
    out_str $X_T13  $row $W_T13 "$t13" "$t13col"
    out_str $X_LAT  $row $W_LAT "$lat" "$C_CYA"
    out_str $X_VER  $row $W_VER "$verdict" "$color"
}

run_scan_table() {
    UI_Y=$((12 + ${#TARGETS[@]} + 1))
    STATUS_BAR_CACHE=""
    draw_status_bar "[ CHECK ] Проверка интернета..."
    write_debug_log "Старт скана" "INFO"
    if ! test_internet_available; then
        draw_status_bar "[ ERROR ] НЕТ ИНТЕРНЕТА!"
        sleep 3
        STATUS_BAR_CACHE=""
        draw_status_bar "$NAV_STR"
        return 1
    fi
    draw_status_bar "[ CACHE ] Загрузка сетевых данных..."
    get_network_info
    rebuild_targets
    UI_Y=$((12 + ${#TARGETS[@]} + 1))
    draw_ui
    draw_status_bar "[ SCAN ] Запуск сканирования..."
    rm -f "$TMP_DIR"/*.res

    local n=${#TARGETS[@]}
    (( n < 1 )) && return 1
    local max_par=$(( ($(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 4) * 3) ))
    (( max_par > 24 )) && max_par=24
    if [[ "${PROXY_ENABLED}" == true ]] || [[ "${PROXY_ENABLED}" == "1" ]]; then (( max_par > 12 )) && max_par=12; fi

    export PROXY_ENABLED PROXY_TYPE PROXY_STR IP_PREFERENCE TLS_MODE HAS_IPV6 OS_MAC

    declare -a queue=()
    local i
    for ((i = 0; i < n; i++)); do
        queue+=("$i")
        local row=$((12 + i))
        out_str $X_VER $row $W_VER "WAIT..." "$C_GRY"
    done
    flush_buffer

    declare -A JDONE
    for ((i = 0; i < n; i++)); do JDONE[$i]=0; done

    local completed=0 aborted=false last_sec=-1
    while (( completed < n )) || (( $(jobs -rp 2>/dev/null | wc -l) > 0 )); do
        while (( $(jobs -rp 2>/dev/null | wc -l) < max_par )) && ((${#queue[@]} > 0)); do
            local idx=${queue[0]}
            queue=("${queue[@]:1}")
            local row=$((12 + idx))
            worker "${TARGETS[$idx]}" "$row" < /dev/null &
        done

        local now_sec
        now_sec=$(date +%s)
        if (( now_sec != last_sec )); then
            last_sec=$now_sec
            local pct=$((completed * 100 / n))
            draw_status_bar "[ SCAN ] Сбор: $completed / $n" "$pct"
        fi

        local inkey=""
        read -t "$READ_TIMEOUT" -n 1 -s inkey 2>/dev/null || true
        if [[ "$inkey" == "q" || "$inkey" == "Q" || "$inkey" == "й" || "$inkey" == "Й" || "$inkey" == $'\e' ]]; then
            aborted=true
            kill $(jobs -p) 2>/dev/null
            wait 2>/dev/null || true
            break
        fi

        for ((i = 0; i < n; i++)); do
            (( JDONE[$i] == 1 )) && continue
            local row=$((12 + i))
            if [[ -f "$TMP_DIR/$row.res" ]]; then
                paint_result_row "$row"
                JDONE[$i]=1
                ((completed++))
            fi
        done
        [[ -n "$FRAME_BUFFER" ]] && flush_buffer
    done
    wait 2>/dev/null || true

    if $aborted; then
        STATUS_BAR_CACHE=""
        draw_status_bar "$NAV_ABORT" ""
        write_debug_log "Скан прерван" "WARN"
    else
        local summary
        summary=$(summarize_verdicts)
        STATUS_BAR_CACHE=""
        draw_status_bar "[ SUCCESS ] Скан OK — $summary" ""
        write_debug_log "Скан завершён: $summary" "INFO"
        HAS_COMPLETED_SCAN=true
        ((RUN_COUNT++))
        config_save
        if (( RUN_COUNT % 10 == 0 )); then
            local lat_tag
            lat_tag=$(github_latest_tag) || lat_tag=""
            if [[ -n "$lat_tag" ]] && version_newer "$SCRIPT_VERSION" "$lat_tag"; then
                sleep 1
                STATUS_BAR_CACHE=""
                draw_status_bar "[ UPDATE ] Новая версия v$lat_tag — нажмите U" ""
                sleep 3
            fi
        fi
    fi
    STATUS_BAR_CACHE=""
    draw_status_bar "$NAV_STR"
    while read -t 0.05 -n 1 -s 2>/dev/null; do : ; done
    return 0
}

deep_trace_flow() {
    write_debug_log "Deep Trace меню" "INFO"
    stty echo
    clear
    echo -e "${C_CYA}Deep Trace — номер строки 1-${#TARGETS[@]} (пустой Enter — отмена):${C_RST}"
    local num
    read -r num
    stty -echo
    [[ -z "$num" ]] && return 0
    [[ "$num" =~ ^[0-9]+$ ]] || return 0
    (( num >= 1 && num <= ${#TARGETS[@]} )) || return 0
    local target="${TARGETS[$((num - 1))]}"
    echo -e "\n${C_CYA}Цель #$num — $target${C_RST}"
    local ip=""
    ip=$(resolve_target_ip "$target" 2>/dev/null || true)
    echo "Резолв: ${ip:-?}"
    echo "--- trace ---"
    if command -v traceroute &>/dev/null; then
        traceroute -n -m 15 -w 2 "$target" 2>&1 | head -n 50
    elif command -v tracepath &>/dev/null; then
        tracepath "$target" 2>&1 | head -n 50
    elif command -v mtr &>/dev/null; then
        mtr -r -c 3 --report-wide "$target" 2>&1 | head -n 40
    else
        echo "[i] Нет traceroute/tracepath/mtr в PATH."
    fi
    echo "--- TLS probe (curl) ---"
    curl -k -s -o /dev/null -w "code=%{response_code} connect=%{time_connect}s\n" -m 15 "https://$target" || echo "curl: ошибка"
    echo -ne "\n${C_CYA}Клавиша для возврата...${C_RST}"
    read -rn1 -s
    echo
}

invoke_update_github() {
    STATUS_BAR_CACHE=""
    draw_status_bar "[ UPDATE ] GitHub..."
    local latest
    latest=$(github_latest_tag) || latest=""
    if [[ -z "$latest" ]]; then
        draw_status_bar "[ UPDATE ] API недоступен или лимит"
        sleep 2
        STATUS_BAR_CACHE=""
        draw_status_bar "$NAV_STR"
        return 1
    fi
    if ! version_newer "$SCRIPT_VERSION" "$latest"; then
        if version_newer "$latest" "$SCRIPT_VERSION"; then
            draw_status_bar "[ UPDATE ] Локальная версия новее GitHub"
            LAST_CHECKED_VERSION="$SCRIPT_VERSION"
        else
            draw_status_bar "[ UPDATE ] Уже последняя ($SCRIPT_VERSION)"
            LAST_CHECKED_VERSION="$SCRIPT_VERSION"
        fi
        config_save
        sleep 2
        STATUS_BAR_CACHE=""
        draw_status_bar "$NAV_STR"
        return 0
    fi
    draw_status_bar "[ UPDATE ] Доступна $latest. Скачать? Y/N"
    stty echo 2>/dev/null || true
    local ans=""
    read -rn1 ans || true
    echo
    stty -echo 2>/dev/null || true
    if [[ "$ans" != "y" && "$ans" != "Y" ]]; then
        LAST_CHECKED_VERSION="$latest"
        config_save
        STATUS_BAR_CACHE=""
        draw_status_bar "$NAV_STR"
        return 0
    fi
    local tmp="${SCRIPT_PATH}.new"
    if ! curl -sL -m 90 -o "$tmp" "https://raw.githubusercontent.com/Shiperoid/YT-DPI/master/YT-DPI.sh"; then
        rm -f "$tmp"
        draw_status_bar "[ UPDATE ] Ошибка загрузки"
        sleep 2
        STATUS_BAR_CACHE=""
        draw_status_bar "$NAV_STR"
        return 1
    fi
    local sz
    sz=$(wc -c < "$tmp" 2>/dev/null || echo 0)
    if (( sz < 8000 )); then
        rm -f "$tmp"
        draw_status_bar "[ UPDATE ] Файл подозрительно мал"
        sleep 2
        STATUS_BAR_CACHE=""
        draw_status_bar "$NAV_STR"
        return 1
    fi
    if ! grep -q 'SCRIPT_VERSION=' "$tmp"; then
        rm -f "$tmp"
        draw_status_bar "[ UPDATE ] Нет маркера SCRIPT_VERSION"
        sleep 2
        STATUS_BAR_CACHE=""
        draw_status_bar "$NAV_STR"
        return 1
    fi
    chmod +x "$tmp" 2>/dev/null || true
    if ! mv -f "$tmp" "$SCRIPT_PATH" 2>/dev/null; then
        rm -f "$tmp"
        draw_status_bar "[ UPDATE ] Не удалось заменить файл (права?)"
        sleep 3
        STATUS_BAR_CACHE=""
        draw_status_bar "$NAV_STR"
        return 1
    fi
    LAST_CHECKED_VERSION="$latest"
    config_save
    draw_status_bar "[ UPDATE ] Успех — перезапустите: bash $SCRIPT_PATH"
    sleep 3
    STATUS_BAR_CACHE=""
    draw_status_bar "$NAV_STR"
}

ui_refresh_after_submenu() {
    get_network_info
    rebuild_targets
    UI_Y=$((12 + ${#TARGETS[@]} + 1))
    draw_ui
    STATUS_BAR_CACHE=""
    draw_status_bar "$NAV_STR"
}

config_load
refresh_env_debug_flags
write_debug_session_header_once

FIRST_RUN=true
LAST_TARGETS_SIG=""
UI_Y=15
f=0

while true; do
    if $FIRST_RUN || $NEED_UI_REDRAW; then
        get_network_info
        rebuild_targets
        UI_Y=$((12 + ${#TARGETS[@]} + 1))
        draw_ui
        STATUS_BAR_CACHE=""
        draw_status_bar "$NAV_STR"
        FIRST_RUN=false
        NEED_UI_REDRAW=false
    fi

    local ts_now
    ts_now=$(date +%s)
    if (( ts_now - LAST_NET_POLL_TS >= 4 )); then
        LAST_NET_POLL_TS=$ts_now
        local sig_before sig_after
        sig_before=$(targets_signature)
        get_network_info
        rebuild_targets
        sig_after=$(targets_signature)
        if [[ "$sig_before" != "$sig_after" ]]; then
            UI_Y=$((12 + ${#TARGETS[@]} + 1))
            draw_ui
            STATUS_BAR_CACHE=""
            draw_status_bar "$NAV_STR"
        fi
    fi

    local key=""
    read -t "$READ_TIMEOUT" -n 1 -s key 2>/dev/null || true

    if $NEED_UI_REDRAW; then continue; fi

    if [[ "$key" == "q" || "$key" == "Q" || "$key" == "й" || "$key" == "Й" ]]; then break
    elif [[ "$key" == $'\e' ]]; then break
    elif [[ "$key" == "h" || "$key" == "H" || "$key" == "р" || "$key" == "Р" ]]; then
        show_help_menu
        ui_refresh_after_submenu
    elif [[ "$key" == "s" || "$key" == "S" || "$key" == "ы" || "$key" == "Ы" ]]; then
        show_settings_menu
        refresh_env_debug_flags
        ui_refresh_after_submenu
    elif [[ "$key" == "p" || "$key" == "P" || "$key" == "з" || "$key" == "З" ]]; then
        show_proxy_menu
        ui_refresh_after_submenu
    elif [[ "$key" == "t" || "$key" == "T" || "$key" == "е" || "$key" == "Е" ]]; then
        test_proxy_connection
        ui_refresh_after_submenu
    elif [[ "$key" == "d" || "$key" == "D" || "$key" == "в" || "$key" == "В" ]]; then
        deep_trace_flow
        ui_refresh_after_submenu
    elif [[ "$key" == "u" || "$key" == "U" || "$key" == "г" || "$key" == "Г" ]]; then
        invoke_update_github
        ui_refresh_after_submenu
    elif [[ "$key" == "r" || "$key" == "R" || "$key" == "к" || "$key" == "К" ]]; then
        STATUS_BAR_CACHE=""
        draw_status_bar "[ WAIT ] SAVING REPORT..."
        LOG="YT-DPI_Report.txt"
        {
            echo "=== YT-DPI REPORT v${SCRIPT_VERSION} ==="
            echo "TIME: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "ISP:  $ISP ($LOC)"
            echo "DNS:  $DNS"
            echo "IpPreference: $IP_PREFERENCE  TlsMode: $TLS_MODE"
            if [[ "${PROXY_ENABLED}" == true ]] || [[ "${PROXY_ENABLED}" == "1" ]]; then echo "PROXY: $PROXY_TYPE $PROXY_HOST:$PROXY_PORT"; else echo "PROXY: [ OFF ]"; fi
            echo "------------------------------------------------------------------------------------------"
            printf "%-38s %-16s %-6s %-8s %-8s %-6s %s\n" "TARGET DOMAIN" "IP ADDRESS" "HTTP" "TLS 1.2" "TLS 1.3" "LAT" "RESULT"
            echo "------------------------------------------------------------------------------------------"
            for i in "${!TARGETS[@]}"; do
                row=$((12 + i))
                if [[ -f "$TMP_DIR/$row.res" ]]; then
                    IFS='|' read -r rip http t12 t13 lat verdict color < "$TMP_DIR/$row.res"
                    if [[ "${PROXY_ENABLED}" == true ]] || [[ "${PROXY_ENABLED}" == "1" ]]; then rip="[ PROXIED ]"; fi
                    printf "%-38s %-16s %-6s %-8s %-8s %-6s %s\n" "${TARGETS[$i]}" "$rip" "$http" "$t12" "$t13" "$lat" "$verdict"
                fi
            done
        } > "$LOG"
        STATUS_BAR_CACHE=""
        draw_status_bar "[ SUCCESS ] SAVED: $(pwd)/$LOG"
        sleep 2
        STATUS_BAR_CACHE=""
        draw_status_bar "$NAV_STR"

    elif [[ "$key" == $'\n' || "$key" == $'\r' ]]; then
        run_scan_table
    fi
done
