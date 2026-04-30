#!/usr/bin/env bash
# YT-DPI bash frontend — синхронизирован с логикой/списком целей YT-DPI.bat v2.2.2 (без TCP traceroute / апдейтера инсталлятора Windows).
# Опционально: jq для JSON-конфига ~/.config/yt-dpi/config.json (поля как в YT-DPI.bat).

# --- ФИКС 1: Отключаем эхо ввода и включаем Alternate Screen Buffer ---
stty -echo
printf "\033[?1049h"
printf "\033[?25l"

cleanup() {
    stty echo
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

TMP_DIR=$(mktemp -d)
E=$'\033'
trap 'cleanup' INT TERM EXIT

SCRIPT_VERSION="2.2.2"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/yt-dpi"
CONFIG_FILE="$CONFIG_DIR/config.json"

# Совместимо по полям с YT-DPI.bat (упрощённо): IpPreference, TlsMode, Proxy, ProxyHistory
export IP_PREFERENCE="IPv6"
export TLS_MODE="Auto"
HAS_IPV6=false

PROXY_ENABLED=false
PROXY_TYPE="HTTP"
PROXY_HOST=""
PROXY_PORT=""
PROXY_USER=""
PROXY_PASS=""
PROXY_STR=""

PROXY_HISTORY=()

STATS_CLEAN=0; STATS_BLOCKED=0; STATS_RST=0; STATS_ERR=0
CDN_LIST=()
TARGETS=()

# Тот же набор доменов, что $BaseTargets в YT-DPI.bat (порядок не важен — ниже сортировка по длине как в Get-Targets).
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

X_DOM=2; X_IP=41; X_HTTP=59; X_T12=67; X_T13=77; X_LAT=87; X_VER=95
C_BLK="${E}[40m"; C_RED="${E}[31m"; C_GRN="${E}[32m"; C_YEL="${E}[33m"
C_MAG="${E}[35m"; C_CYA="${E}[36m"; C_WHT="${E}[97m"; C_GRY="${E}[90m"; C_RST="${E}[0m"

NAV_STR="[ READY ] [ENTER] SCAN | [S] SETTINGS | [P] PROXY | [T] TEST | [R] REPORT | [H] HELP | [Q] QUIT"
NAV_SCAN="[ BUSY ] SCANNING IN PROGRESS... PRESS [Q] TO ABORT"
NAV_ABORT="[ ABORTED ] SCAN STOPPED. [ENTER] SCAN | [S] SETTINGS | [P] PROXY | [T] TEST | [R] REPORT | [H] HELP | [Q] QUIT"
NAV_DONE="[ SUCCESS ] SCAN FINISHED. [ENTER] SCAN | [S] SETTINGS | [P] PROXY | [T] TEST | [R] REPORT | [H] HELP | [Q] QUIT"

FRAME_BUFFER=""
out_str() {
    local x=$1 y=$2 w=$3 text=$4 color=$5
    local padded
    printf -v padded "%-${w}s" "$text"
    FRAME_BUFFER+="${E}[${y};${x}H${color}${padded}${C_RST}"
}
flush_buffer() { printf "%b" "$FRAME_BUFFER"; FRAME_BUFFER=""; }

have_jq() { command -v jq &>/dev/null; }

config_save() {
    have_jq || return 0
    mkdir -p "$CONFIG_DIR" || return 1
    local hist_json
    hist_json=$(printf '%s\n' "${PROXY_HISTORY[@]}" | jq -R . 2>/dev/null | jq -s . 2>/dev/null) || hist_json='[]'
    local pe=false
    if [[ "${PROXY_ENABLED}" == true ]] || [[ "${PROXY_ENABLED}" == "1" ]]; then pe=true; fi
    local pj port_safe
    port_safe="${PROXY_PORT:-0}"
    [[ "$port_safe" =~ ^[0-9]+$ ]] || port_safe=0
    jq -n \
        --arg IpPreference "$IP_PREFERENCE" \
        --arg TlsMode "$TLS_MODE" \
        --argjson ProxyEnabled "$pe" \
        --arg Type "${PROXY_TYPE:-HTTP}" \
        --arg Host "${PROXY_HOST:-}" \
        --argjson Port "$port_safe" \
        --arg User "${PROXY_USER:-}" \
        --arg Pass "${PROXY_PASS:-}" \
        --argjson History "$hist_json" \
        '{IpPreference:$IpPreference,TlsMode:$TlsMode,Proxy:{Enabled:$ProxyEnabled,Type:$Type,Host:$Host,Port:$Port,User:$User,Pass:$Pass},ProxyHistory:$History}' \
        > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
}

config_load() {
    have_jq || return 0
    [[ -f "$CONFIG_FILE" ]] || return 0
    IP_PREFERENCE=$(jq -r '.IpPreference // "IPv6"' "$CONFIG_FILE")
    TLS_MODE=$(jq -r '.TlsMode // "Auto"' "$CONFIG_FILE")
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
        if [[ "$PROXY_TYPE" == "SOCKS5" ]]; then PROXY_STR="${PROXY_STR/socks5:\/\//socks5h:\/\/}"; fi
    fi
}

detect_ipv6() {
    HAS_IPV6=false
    if command -v getent &>/dev/null; then
        if getent ahostsv6 ipv6.google.com &>/dev/null; then HAS_IPV6=true; return; fi
    fi
    if command -v ping6 &>/dev/null; then
        if ping6 -c 1 -W 1 2001:4860:4860::8888 &>/dev/null; then HAS_IPV6=true; fi
    fi
}

# Как Get-Targets в .bat: базовый список + CDN_LIST + текущий CDN, уникально и сортировка по длине строки.
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
    out_str 1 1 0 '██╗   ██╗████████╗    ██████╗ ██████╗ ██╗  _    _____    ____' "$C_GRN"
    out_str 1 2 0 '╚██╗ ██╔╝╚══██╔══╝    ██╔══██╗██╔══██╗██║ | |  / /__ \  / __ \' "$C_GRN"
    out_str 1 3 0 ' ╚████╔╝    ██║ █████╗██║  ██║██████╔╝██║ | | / /__/ / / / / /' "$C_GRN"
    out_str 1 4 0 '  ╚██╔╝     ██║ ╚════╝██║  ██║██╔═══╝ ██║ | |/ // __/_/ /_/ /' "$C_GRN"
    out_str 1 5 0 '   ██╝      ██╝       ██████╝ ██╝     ██╝ |___//____(_)____/' "$C_GRN"

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
        out_str $X_DOM $row 38 "${TARGETS[$i]}" "$C_GRY"
        out_str $X_IP   $row 16 "---.---.---.---" "$C_GRY"
        out_str $X_HTTP $row 6 "--" "$C_GRY"
        out_str $X_T12  $row 8 "--" "$C_GRY"
        out_str $X_T13  $row 8 "--" "$C_GRY"
        out_str $X_LAT  $row 6 "----" "$C_GRY"
        out_str $X_VER  $row 30 "IDLE" "$C_GRY"
    done
    out_str 0 $((12 + ${#TARGETS[@]})) 0 "$l" "$C_CYA"
    flush_buffer
}

show_help() {
    clear
    echo -e "${C_CYA}=== YT-DPI v${SCRIPT_VERSION} : GUIDE ===${C_RST}"
    echo -e "\n${C_YEL}[ STATUS CODES ]${C_RST}"
    echo -e "  ${C_GRN}OK   - Connection successful.${C_RST}"
    echo -e "  ${C_RED}RST  - Connection Reset. DPI injected a TCP RST packet.${C_RST}"
    echo -e "  ${C_RED}DRP  - Connection Dropped (Blackholed/Timeout).${C_RST}"
    echo -e "  ${C_GRY}N/A  - Not Available (e.g. lack of TLS 1.3 support).${C_RST}"
    echo -e "  ${C_RED}FAIL - Connection failed or general error.${C_RST}"

    echo -e "\n${C_YEL}[ RESULT ]${C_RST}"
    echo -e "  ${C_GRN}AVAILABLE     - TLS passed. Domain is fully accessible.${C_RST}"
    echo -e "  ${C_YEL}DPI BLOCK     - HTTP works, but TLS is blocked/dropped.${C_RST}"
    echo -e "  ${C_YEL}THROTTLED    - HTTP works, but one TLS version is blocked.${C_RST}"
    echo -e "  ${C_RED}IP  BLOCK     - Both HTTP and TLS are unreachable.${C_RST}"
    echo -e "  ${C_RED}ROUTING ERROR - Network issues, proxy failure, bad routing.${C_RST}"

    echo -ne "\n${C_CYA}PRESS ANY KEY TO RETURN...${C_RST}"
    read -r -n 1 -s
}

show_settings_menu() {
    stty echo
    clear
    echo -e "${C_CYA}=== SETTINGS (как в YT-DPI.bat, упрощённо) ===${C_RST}"
    echo -e "  IpPreference: ${C_YEL}$IP_PREFERENCE${C_RST}   TlsMode: ${C_YEL}$TLS_MODE${C_RST}"
    echo -e "  IPv6 detected: ${C_YEL}$HAS_IPV6${C_RST}"
    echo -e "\n${C_CYA}Выберите:${C_RST}"
    echo -e "  ${C_GRY}1${C_RST} — IpPreference: IPv6"
    echo -e "  ${C_GRY}2${C_RST} — IpPreference: IPv4"
    echo -e "  ${C_GRY}3${C_RST} — TlsMode: Auto"
    echo -e "  ${C_GRY}4${C_RST} — TlsMode: TLS12"
    echo -e "  ${C_GRY}5${C_RST} — TlsMode: TLS13"
    echo -e "  ${C_GRY}Enter${C_RST} — назад"
    echo -ne "\n${C_YEL}> ${C_RST}"
    local c
    read -r c
    stty -echo
    case "$c" in
        1) IP_PREFERENCE="IPv6" ;;
        2) IP_PREFERENCE="IPv4" ;;
        3) TLS_MODE="Auto" ;;
        4) TLS_MODE="TLS12" ;;
        5) TLS_MODE="TLS13" ;;
        *) return 0 ;;
    esac
    config_save
    echo -e "\n${C_GRN}[OK] Сохранено.${C_RST}"
    sleep 1
}

# Выбор записи из истории прокси (формат TYPE://[user:*****@]host:port). Возвращает 0 если применено.
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
    proxy_history_add
    return 0
}

show_proxy_menu() {
    stty echo
    clear
    echo -e "${C_CYA}=== НАСТРОЙКИ ПРОКСИ (YT-DPI v${SCRIPT_VERSION}) ===${C_RST}"

    if [[ "${PROXY_ENABLED}" == true ]] || [[ "${PROXY_ENABLED}" == "1" ]]; then
        echo -e "  [ СТАТУС ]  ${C_GRN}ВКЛЮЧЕН${C_RST}"
        echo -e "  [ ТИП ]     ${C_YEL}$PROXY_TYPE${C_RST}"
        echo -e "  [ АДРЕС ]   ${C_YEL}$PROXY_HOST:$PROXY_PORT${C_RST}"
        if [ -n "$PROXY_USER" ]; then echo -e "  [ ЛОГИН ]   ${C_YEL}$PROXY_USER${C_RST}"; fi
    else
        echo -e "  [ СТАТУС ]  ${C_GRY}ОТКЛЮЧЕН${C_RST}"
    fi

    if ((${#PROXY_HISTORY[@]} > 0)); then
        echo -e "\n${C_CYA}ИСТОРИЯ (номер для выбора):${C_RST}"
        local hi
        for (( hi=0; hi<${#PROXY_HISTORY[@]}; hi++ )); do
            echo -e "    $((hi+1)). ${PROXY_HISTORY[$hi]}"
        done
        echo -e "    ${C_GRY}0. Очистить историю (CLEAR)${C_RST}"
    fi

    echo -e "\n${C_CYA}Команды:${C_RST} ${C_GRY}TEST${C_RST} — проверить текущий прокси | ${C_GRY}CLEAR${C_RST} — очистить историю"
    echo -e "${C_CYA}Форматы:${C_RST} host:port | socks5://... | http://user:pass@host:port | ${C_GRY}OFF/0${C_RST}"

    echo -ne "\n${C_YEL}> Введите прокси (или номер из истории): ${C_RST}"
    local px_input
    read -r px_input
    stty -echo

    px_input=$(echo "$px_input" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [[ -z "$px_input" ]] && return 0

    shopt -s nocasematch
    if [[ "$px_input" == "TEST" ]]; then
        shopt -u nocasematch
        test_proxy
        return 0
    fi
    if [[ "$px_input" == "CLEAR" ]]; then
        shopt -u nocasematch
        PROXY_HISTORY=()
        config_save
        echo -e "\n${C_GRN}[OK] История очищена.${C_RST}"; sleep 1
        return 0
    fi
    shopt -u nocasematch

    if [[ "$px_input" =~ ^[0-9]+$ ]]; then
        local n=$px_input
        if (( n == 0 )) && ((${#PROXY_HISTORY[@]} > 0)); then
            PROXY_HISTORY=()
            config_save
            echo -e "\n${C_GRN}[OK] История очищена.${C_RST}"; sleep 1
            return 0
        fi
        if (( n >= 1 && n <= ${#PROXY_HISTORY[@]} )); then
            if apply_proxy_history_entry "${PROXY_HISTORY[$((n-1))]}"; then
                echo -e "\n${C_GRN}[OK] Прокси из истории применён.${C_RST}"; sleep 1
            fi
            return 0
        fi
    fi

    if [[ "$px_input" == "0" || "$px_input" == "off" || "$px_input" == "OFF" ]]; then
        PROXY_ENABLED=false
        PROXY_TYPE="HTTP"; PROXY_HOST=""; PROXY_PORT=""; PROXY_USER=""; PROXY_PASS=""; PROXY_STR=""
        config_save
        echo -e "\n${C_GRN}[OK] Прокси отключён.${C_RST}"; sleep 1
        return 0
    fi

    local re="^((http|https|socks5)://)?(([^:]+):([^@]+)@)?([^:/]+|\[[a-fA-F0-9:]+\]):([0-9]{1,5})$"

    shopt -s nocasematch
    if [[ "$px_input" =~ $re ]]; then
        shopt -u nocasematch

        local t="${BASH_REMATCH[2]}" u="${BASH_REMATCH[4]}" pw="${BASH_REMATCH[5]}"
        local h="${BASH_REMATCH[6]}" p="${BASH_REMATCH[7]}"

        if (( p <= 0 || p > 65535 )); then
            echo -e "\n${C_RED}[x] Неверный порт.${C_RST}"; sleep 2
            return 0
        fi

        local userpass_str=""
        if [[ -n "$u" && -n "$pw" ]]; then userpass_str="${u}:${pw}@"; fi

        if [[ -z "$t" ]]; then
            echo -e "\n${C_GRY}[*] Автоопределение типа...${C_RST}"
            local detected="HTTP"
            echo -ne "  -> SOCKS5... ${C_GRY}"
            if curl -s -m 3 -x "socks5://${userpass_str}${h}:${p}" -I "http://google.com" -o /dev/null; then
                detected="SOCKS5"; echo -e "${C_GRN}OK${C_RST}"
            else
                echo -e "${C_RED}нет${C_RST}"; echo -ne "  -> HTTP... ${C_GRY}"
                if curl -s -m 3 -x "http://${userpass_str}${h}:${p}" -I "http://google.com" -o /dev/null; then
                    detected="HTTP"; echo -e "${C_GRN}OK${C_RST}"
                else
                    echo -e "${C_RED}нет${C_RST}"
                    echo -e "  ${C_GRY}[!] Оставляем HTTP.${C_RST}"
                fi
            fi
            t="$detected"
        fi

        PROXY_ENABLED=true
        PROXY_TYPE=$(echo "$t" | tr 'a-z' 'A-Z')
        PROXY_HOST="$h"; PROXY_PORT="$p"; PROXY_USER="$u"; PROXY_PASS="$pw"

        local t_lower=$(echo "$PROXY_TYPE" | tr 'A-Z' 'a-z')
        PROXY_STR="${t_lower}://${userpass_str}${PROXY_HOST}:${PROXY_PORT}"
        if [[ "$PROXY_TYPE" == "SOCKS5" ]]; then PROXY_STR="${PROXY_STR/socks5:\/\//socks5h:\/\/}"; fi

        proxy_history_add
        echo -e "\n${C_GRN}[OK] Прокси сохранён.${C_RST}"; sleep 1
    else
        shopt -u nocasematch
        echo -e "\n${C_RED}[x] Неверный формат.${C_RST}"; sleep 2
    fi
}

test_proxy() {
    clear
    echo -e "${C_CYA}=== ТЕСТ ПРОКСИ ===${C_RST}"
    if [[ "${PROXY_ENABLED}" != true ]] && [[ "${PROXY_ENABLED}" != "1" ]]; then
        echo -e "${C_RED}Прокси отключён.${C_RST}"; sleep 2
        return
    fi

    echo -e "${C_YEL}Подключение к google.com:80 через $PROXY_TYPE...${C_RST}"
    local out
    out=$(curl -s -w "\n%{time_connect}" -m 3 -x "$PROXY_STR" -I "http://google.com")
    if [ $? -eq 0 ]; then
        local ms=$(echo "$out" | tail -n1 | awk '{print int($1*1000)}')
        echo -e "${C_GRN}OK за ${ms} мс.${C_RST}"
    else
        echo -e "${C_RED}Ошибка соединения.${C_RST}"
    fi
    echo -ne "\n${C_CYA}Нажмите любую клавишу...${C_RST}"; read -r -n 1 -s
}

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

    local http_out
    http_out=$(curl -s -m 2 $px_args -I "http://$target" -A "curl/7.88.1" -w "\n%{time_total}" 2>&1)
    if [ $? -eq 0 ]; then
        http="OK"; lat=$(echo "$http_out" | tail -n1 | tr ',' '.' | awk '{v=int($1*1000); if(v==0) v=1; print v"ms"}')
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
        if { [ "$t12" == "RST" ] || [ "$t13" == "RST" ]; } && [ "$http" == "ERR" ]; then
            verdict="ROUTING ERROR"; color="$C_RED"
        else
            verdict="IP BLOCK"; color="$C_RED"
        fi
    fi

    echo "$ip|$http|$t12|$t13|$lat|$verdict|$color" > "$TMP_DIR/$row.res"
}

config_load

FIRST_RUN=true
FRAMES=("[=   ]" "[ =  ]" "[  = ]" "[   =]" "[  = ]" "[ =  ]")
f=0

while true; do
    if $FIRST_RUN; then
        get_network_info
        rebuild_targets
        draw_ui
        UI_Y=$((12 + ${#TARGETS[@]} + 1))
        out_str 2 $UI_Y 121 "$NAV_STR" "$C_WHT"; flush_buffer
        FIRST_RUN=false
    fi

    read -t $READ_TIMEOUT -n 1 -s key
    READ_STATUS=$?

    if [[ "$key" == "q" || "$key" == "Q" || "$key" == $'\e' ]]; then break
    elif [[ "$key" == "h" || "$key" == "H" ]]; then show_help; draw_ui; out_str 2 $UI_Y 121 "$NAV_STR" "$C_WHT"; flush_buffer
    elif [[ "$key" == "s" || "$key" == "S" ]]; then show_settings_menu; get_network_info; rebuild_targets; draw_ui; out_str 2 $UI_Y 121 "$NAV_STR" "$C_WHT"; flush_buffer
    elif [[ "$key" == "p" || "$key" == "P" ]]; then show_proxy_menu; get_network_info; rebuild_targets; draw_ui; out_str 2 $UI_Y 121 "$NAV_STR" "$C_WHT"; flush_buffer
    elif [[ "$key" == "t" || "$key" == "T" ]]; then test_proxy; draw_ui; out_str 2 $UI_Y 121 "$NAV_STR" "$C_WHT"; flush_buffer
    elif [[ "$key" == "r" || "$key" == "R" ]]; then
        out_str 2 $UI_Y 121 "[ WAIT ] SAVING REPORT..." "$C_CYA"; flush_buffer
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
                if [ -f "$TMP_DIR/$row.res" ]; then
                    IFS='|' read -r rip http t12 t13 lat verdict color < "$TMP_DIR/$row.res"
                    if [[ "${PROXY_ENABLED}" == true ]] || [[ "${PROXY_ENABLED}" == "1" ]]; then rip="[ PROXIED ]"; fi
                    printf "%-38s %-16s %-6s %-8s %-8s %-6s %s\n" "${TARGETS[$i]}" "$rip" "$http" "$t12" "$t13" "$lat" "$verdict"
                fi
            done
        } > "$LOG"
        out_str 2 $UI_Y 121 "[ SUCCESS ] SAVED: $(pwd)/$LOG" "$C_GRN"; flush_buffer
        sleep 2; out_str 2 $UI_Y 121 "$NAV_STR" "$C_WHT"; flush_buffer

    elif [[ -z "$key" && $READ_STATUS -eq 0 ]]; then
        STATS_CLEAN=0; STATS_BLOCKED=0; STATS_RST=0; STATS_ERR=0

        out_str 2 $UI_Y 121 "[ WAIT ] REFRESHING NETWORK STATE..." "$C_CYA"; flush_buffer
        get_network_info
        rebuild_targets

        draw_ui; UI_Y=$((12 + ${#TARGETS[@]} + 1))
        out_str 2 $UI_Y 121 "$NAV_SCAN" "$C_YEL"; flush_buffer

        rm -f "$TMP_DIR"/*.res
        JOB_STATE=()
        ACTIVE_JOBS=${#TARGETS[@]}

        export PROXY_ENABLED PROXY_TYPE PROXY_STR IP_PREFERENCE TLS_MODE HAS_IPV6 OS_MAC

        for i in "${!TARGETS[@]}"; do
            row=$((12 + i))
            out_str $X_VER $row 30 "PREPARING..." "$C_GRY"
            JOB_STATE[$i]=1
            worker "${TARGETS[$i]}" "$row" < /dev/null &
        done
        flush_buffer

        aborted=false
        while [ $ACTIVE_JOBS -gt 0 ]; do
            ((f++))

            if (( f % 5 == 0 )); then
                if $OS_MAC; then ram=$(ps -o rss= -p $$ | awk '{print int($1/1024)"MB"}')
                else ram=$(awk '/VmRSS/ {print int($2/1024)"MB"}' /proc/$$/status 2>/dev/null || echo "N/A"); fi

                printf -v info_str "[ RAM: %-5s | JOBS: %-2d ]" "$ram" "$ACTIVE_JOBS"
                out_str 95 1 28 "$info_str" "$C_GRY"
                printf -v stat1 "[ BLOCKS: %-2d | RST: %-2d ]" "$STATS_BLOCKED" "$STATS_RST"
                out_str 95 2 28 "$stat1" "$C_GRY"
                printf -v stat2 "[ CLEAN:  %-2d | ERR: %-2d ]" "$STATS_CLEAN" "$STATS_ERR"
                out_str 95 3 28 "$stat2" "$C_GRY"
            fi

            read -t $READ_TIMEOUT -n 1 -s inkey
            if [[ "$inkey" == "q" || "$inkey" == "Q" || "$inkey" == $'\e' ]]; then aborted=true; break; fi

            for i in "${!TARGETS[@]}"; do
                if [ "${JOB_STATE[$i]}" -eq 0 ]; then continue; fi
                row=$((12 + i))

                if [ -f "$TMP_DIR/$row.res" ]; then
                    IFS='|' read -r ip http t12 t13 lat verdict color < "$TMP_DIR/$row.res"

                    if [[ "$verdict" == *"AVAILABLE"* ]]; then ((STATS_CLEAN++))
                    elif [[ "$verdict" == *"BLOCK"* ]]; then ((STATS_BLOCKED++))
                    elif [[ "$verdict" == *"ERR"* || "$verdict" == *"CRASH"* ]]; then ((STATS_ERR++))
                    fi
                    if [[ "$t12" == "RST" || "$t13" == "RST" ]]; then ((STATS_RST++)); fi

                    out_str $X_IP   $row 16 "$ip" "$C_GRY"
                    [ "$http" == "OK" ] && hcol="$C_GRN" || hcol="$C_RED"
                    out_str $X_HTTP $row 6 "$http" "$hcol"
                    [ "$t12" == "OK" ] && t12col="$C_GRN" || t12col="$C_RED"
                    [[ "$t12" == "---" ]] && t12col="$C_GRY"
                    out_str $X_T12  $row 8 "$t12" "$t12col"
                    if [ "$t13" == "OK" ]; then t13col="$C_GRN"
                    elif [ "$t13" == "N/A" ] || [ "$t13" == "---" ]; then t13col="$C_GRY"
                    else t13col="$C_RED"; fi
                    out_str $X_T13  $row 8 "$t13" "$t13col"
                    out_str $X_LAT  $row 6 "$lat" "$C_CYA"
                    out_str $X_VER  $row 30 "$verdict" "$color"

                    JOB_STATE[$i]=0
                    ((ACTIVE_JOBS--))
                else
                    anim_idx=$(( (f + row) % 6 ))
                    out_str $X_VER $row 30 "SCANNING ${FRAMES[$anim_idx]}" "$C_CYA"

                    if (( f % 4 == 0 )); then
                        if [[ "${PROXY_ENABLED}" == true ]] || [[ "${PROXY_ENABLED}" == "1" ]]; then
                            out_str $X_IP $row 16 "[ *PROXIED* ]" "$C_GRY"
                        else
                            out_str $X_IP $row 16 "$((RANDOM%245+10)).$((RANDOM%245+10)).$row.$((f%255))" "$C_GRY"
                        fi
                        out_str $X_LAT $row 6 "$((RANDOM%84+15))ms" "$C_GRY"
                    fi
                fi
            done
            flush_buffer
        done

        if $aborted; then
            kill $(jobs -p) 2>/dev/null
            out_str 2 $UI_Y 121 "$NAV_ABORT" "$C_RED"
        else
            out_str 2 $UI_Y 121 "$NAV_DONE" "$C_GRN"
        fi
        flush_buffer
        while read -t 0.1 -n 1 -s; do : ; done
    fi
done
