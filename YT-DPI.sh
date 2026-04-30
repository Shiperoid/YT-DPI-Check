#!/usr/bin/env bash

# --- ФИКС 1: Отключаем эхо ввода и включаем Alternate Screen Buffer ---
# Это предотвратит "сдвиг" строк при нажатии Enter и скроллинг
stty -echo
printf "\033[?1049h" # Enter Alt Buffer
printf "\033[?25l"   # Hide Cursor

# Функция восстановления при выходе (Ctrl+C или Q)
cleanup() {
    stty echo
    printf "\033[?1049l" # Exit Alt Buffer
    printf "\033[?25h"   # Show Cursor
    rm -rf "$TMP_DIR"
    exit
}

unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY

if [ -x "/usr/bin/curl" ]; then
    curl() {
        "/usr/bin/curl" "$@"
    }
fi

# Проверка зависимостей
for cmd in curl awk; do
    if ! command -v $cmd &> /dev/null; then 
        stty echo; printf "\033[?1049l"; echo "Error: $cmd is required."; exit 1; 
    fi
done

OS_MAC=false
if [[ "$OSTYPE" == "darwin"* ]]; then OS_MAC=true; fi

READ_TIMEOUT="0.05"
if (( BASH_VERSINFO[0] < 4 )); then READ_TIMEOUT="1"; fi

TMP_DIR=$(mktemp -d)
E=$'\033'
trap 'cleanup' INT TERM EXIT

# --- ГЛОБАЛЬНЫЕ НАСТРОЙКИ ---
export PROXY_ENABLED=false
export PROXY_TYPE="HTTP"
export PROXY_HOST=""
export PROXY_PORT=""
export PROXY_USER=""
export PROXY_PASS=""
export PROXY_STR=""

STATS_CLEAN=0; STATS_BLOCKED=0; STATS_RST=0; STATS_ERR=0
CDN_LIST=()

# --- ТВОЙ НОВЫЙ СПИСОК (BASH ARRAY FORMAT) ---
BASE_TARGETS=(
    # 1. Основные интерфейсы
    "youtube.com" 
    "www.youtube.com"
    "m.youtube.com"
    "youtu.be"

    # 2. Видео-трафик
    "manifest.googlevideo.com" 
    "redirector.googlevideo.com"

    # 3. Контент и оформление
    "i.ytimg.com"
    "s.ytimg.com"
    "yt3.ggpht.com"
    "yt4.ggpht.com"
    "www.youtube-nocookie.com"

    # 4. API и сервисы
    "youtubei.googleapis.com" 
    "s.youtube.com"
    "video.google.com"
    "youtubeembeddedplayer.googleapis.com"

    # 5. Служебный трафик
    "signaler-pa.youtube.com"
    "play.google.com"
    "googleapis.com"
)

X_DOM=2; X_IP=41; X_HTTP=59; X_T12=67; X_T13=77; X_LAT=87; X_VER=95
C_BLK="${E}[40m"; C_RED="${E}[31m"; C_GRN="${E}[32m"; C_YEL="${E}[33m"
C_MAG="${E}[35m"; C_CYA="${E}[36m"; C_WHT="${E}[97m"; C_GRY="${E}[90m"; C_RST="${E}[0m"

# --- ДВИЖОК ОТРИСОВКИ ---
FRAME_BUFFER=""
out_str() {
    local x=$1 y=$2 w=$3 text=$4 color=$5
    local padded
    printf -v padded "%-${w}s" "$text"
    FRAME_BUFFER+="${E}[${y};${x}H${color}${padded}${C_RST}"
}
flush_buffer() { printf "%b" "$FRAME_BUFFER"; FRAME_BUFFER=""; }

# --- СЕТЕВЫЕ ФУНКЦИИ ---
get_network_info() {
    DNS=$(grep nameserver /etc/resolv.conf 2>/dev/null | head -n 1 | awk '{print $2}' | tr -d '\r\n')
    [ -z "$DNS" ] && DNS="UNKNOWN"

    local px_args=""
    if $PROXY_ENABLED; then px_args="-x $PROXY_STR"; fi

    # --- Динамический сбор CDN через DNS ---
    CDN_LIST=()
    local cdn_prefixes=( r1 r2 r3 rr1 rr2 rr3 rr4 rr5 )
    local pfx host
    for pfx in "${cdn_prefixes[@]}"; do
        host="${pfx}.googlevideo.com"
        if command -v getent &>/dev/null; then
            if getent ahostsv4 "$host" &>/dev/null; then
                CDN_LIST+=("$host")
            fi
        elif command -v nslookup &>/dev/null; then
            if nslookup "$host" &>/dev/null; then
                CDN_LIST+=("$host")
            fi
        fi
    done

    # Fallback: если DNS ничего не дал – старый метод через report_mapping
    if [ ${#CDN_LIST[@]} -eq 0 ]; then
        local rnd=$RANDOM
        local cdn_raw=$(curl -s -m 2 $px_args "http://redirector.googlevideo.com/report_mapping?di=no&nocache=$rnd")
        if [[ "$cdn_raw" =~ =\>\ ([a-zA-Z0-9-]+) ]]; then
            CDN_LIST+=("r1.${BASH_REMATCH[1]}.googlevideo.com")
        else
            CDN_LIST+=("manifest.googlevideo.com")
        fi
    fi

    # Для отображения в UI берём первый CDN
    CDN="${CDN_LIST[0]}"

    # Гео-информация
    ISP="UNKNOWN"; LOC="UNKNOWN"
    local geo_raw=$(curl -s -A "curl/7.88.1" -m 2 $px_args "http://ip-api.com/line/?fields=status,countryCode,city,isp")
    if [ "$(echo "$geo_raw" | sed -n '1p' | tr -d '\r\n')" == "success" ]; then
        LOC="$(echo "$geo_raw" | sed -n '3p' | tr -d '\r\n'), $(echo "$geo_raw" | sed -n '2p' | tr -d '\r\n')"
        ISP=$(echo "$geo_raw" | sed -n '4p' | tr -d '\r\n' | sed -E 's/ (LLC|Inc\.?|Ltd\.?|sp\. z o\.o\.|CJSC|OJSC|PJSC|PAO|ZAO|OOO|JSC)//g')
        [ ${#ISP} -gt 25 ] && ISP="${ISP:0:22}..."
    fi
}

draw_ui() {
    clear; FRAME_BUFFER=""
    out_str 1 1 0 '██╗   ██╗████████╗    ██████╗ ██████╗ ██╗  _    _____    ____' "$C_GRN"
    out_str 1 2 0 '╚██╗ ██╔╝╚══██╔══╝    ██╔══██╗██╔══██╗██║ | |  / /__ \  / __ \' "$C_GRN"
    out_str 1 3 0 ' ╚████╔╝    ██║ █████╗██║  ██║██████╔╝██║ | | / /__/ / / / / /' "$C_GRN"
    out_str 1 4 0 '  ╚██╔╝     ██║ ╚════╝██║  ██║██╔═══╝ ██║ | |/ // __/_/ /_/ /' "$C_GRN"
    out_str 1 5 0 '   ██╝      ██╝       ██████╝ ██╝     ██╝ |___//____(_)____/' "$C_GRN"

    out_str 65 1 0 "> SYSTEM STATUS: [ ONLINE ]" "$C_GRN"
    out_str 65 2 50 "> ACTIVE DNS: $DNS" "$C_CYA"
    out_str 65 3 0 "> ENGINE: Potato 1.1-stable " "$C_RED"
    out_str 65 4 50 "> DETECTED CDN: $CDN" "$C_YEL"
    out_str 65 5 0 "> AUTHOR: github.com/Shiperoid" "$C_GRY"
    out_str 65 6 58 "> ISP / LOC: $ISP ($LOC)" "$C_MAG"

    if $PROXY_ENABLED; then px_stat="> PROXY: $PROXY_TYPE $PROXY_HOST:$PROXY_PORT"; else px_stat="> PROXY: OFF"; fi
    out_str 65 7 58 "$px_stat" "$C_YEL"

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
    echo -e "${C_CYA}=== YT-DPI : MINI GUIDE ===${C_RST}"
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
    echo -e "  ${C_RED}ROUTING ERROR - Network issues, proxy failure, or bad routing.${C_RST}"

    echo -ne "\n${C_CYA}PRESS ANY KEY TO RETURN TO SCANNER...${C_RST}"
    read -r -n 1 -s
}

show_proxy_menu() {
    stty echo # Включаем эхо временно для ввода
    clear
    echo -e "${C_CYA}=== НАСТРОЙКИ ПРОКСИ ===${C_RST}"
    
    if $PROXY_ENABLED; then
        echo -e "  [ СТАТУС ]  ${C_GRN}ВКЛЮЧЕН${C_RST}"
        echo -e "  [ ТИП ]     ${C_YEL}$PROXY_TYPE${C_RST}"
        echo -e "  [ АДРЕС ]   ${C_YEL}$PROXY_HOST:$PROXY_PORT${C_RST}"
        if [ -n "$PROXY_USER" ]; then echo -e "  [ ЛОГИН ]   ${C_YEL}$PROXY_USER${C_RST}"; fi
    else 
        echo -e "  [ СТАТУС ]  ${C_GRY}ОТКЛЮЧЕН${C_RST}"
    fi

    echo -e "\n${C_CYA}=== ПОДДЕРЖИВАЕМЫЕ ТИПЫ: HTTP / HTTPS / SOCKS5 ===${C_RST}"
    echo -e "  1. Автоопределение:     ${C_GRY}127.0.0.1:8080 ${C_GRY}(Скрипт сам поймет тип)${C_RST}"
    echo -e "  2. Явное указание:      ${C_GRY}socks5://192.168.1.1:1080${C_RST}"
    echo -e "  3. С логином и паролем: ${C_GRY}http://user:pass@10.0.0.1:3128${C_RST}"
    echo -e "  4. Отключить прокси:    ${C_GRY}Введите 0 или OFF${C_RST}"
    echo -e "  5. Отмена:              ${C_GRY}Просто нажмите Enter${C_RST}"

    echo -ne "\n${C_YEL}> Введите прокси: ${C_RST}"
    read -r px_input
    stty -echo # Выключаем эхо обратно

    if [[ -z "$px_input" ]]; then return; fi
    
    if [[ "$px_input" == "0" || "$px_input" == "off" || "$px_input" == "OFF" ]]; then
        PROXY_ENABLED=false
        PROXY_TYPE="HTTP"; PROXY_HOST=""; PROXY_PORT=""; PROXY_USER=""; PROXY_PASS=""; PROXY_STR=""
        echo -e "\n${C_GRN}[V] Прокси успешно отключен.${C_RST}"; sleep 1
        return
    fi

    local re="^((http|https|socks5)://)?(([^:]+):([^@]+)@)?([^:/]+|\[[a-fA-F0-9:]+\]):([0-9]{1,5})$"
    
    shopt -s nocasematch
    if [[ "$px_input" =~ $re ]]; then
        shopt -u nocasematch
        
        local t="${BASH_REMATCH[2]}"; local u="${BASH_REMATCH[4]}"; local pw="${BASH_REMATCH[5]}"
        local h="${BASH_REMATCH[6]}"; local p="${BASH_REMATCH[7]}"

        if (( p <= 0 || p > 65535 )); then
            echo -e "\n${C_RED}[x] Ошибка: Неверный порт!${C_RST}"; sleep 2; return
        fi

        local userpass_str=""
        if [[ -n "$u" && -n "$pw" ]]; then userpass_str="${u}:${pw}@"; fi

        if [[ -z "$t" ]]; then
            echo -e "\n${C_GRY}[*] Тип не указан. Запускаю автоопределение...${C_RST}"
            local detected="HTTP"
            echo -ne "  -> Проверка SOCKS5... ${C_GRY}"
            if curl -s -m 3 -x "socks5://${userpass_str}${h}:${p}" -I "http://google.com" -o /dev/null; then
                detected="SOCKS5"; echo -e "${C_GRN}OK!${C_RST}"
            else
                echo -e "${C_RED}Нет${C_RST}"; echo -ne "  -> Проверка HTTP...   ${C_GRY}"
                if curl -s -m 3 -x "http://${userpass_str}${h}:${p}" -I "http://google.com" -o /dev/null; then
                    detected="HTTP"; echo -e "${C_GRN}OK!${C_RST}"
                else
                    echo -e "${C_RED}Нет${C_RST}"
                    echo -e "  ${C_GRY}[!] Сервер не ответил на тесты. Оставляем HTTP по умолчанию.${C_RST}"
                fi
            fi
            t="$detected"
            local t_upper=$(echo "$t" | tr 'a-z' 'A-Z')
            echo -e "  ${C_CYA}=> Итоговый тип: ${t_upper}${C_RST}"
        fi

        PROXY_ENABLED=true
        PROXY_TYPE=$(echo "$t" | tr 'a-z' 'A-Z')
        PROXY_HOST="$h"; PROXY_PORT="$p"; PROXY_USER="$u"; PROXY_PASS="$pw"
        
        local t_lower=$(echo "$PROXY_TYPE" | tr 'A-Z' 'a-z')
        PROXY_STR="${t_lower}://${userpass_str}${PROXY_HOST}:${PROXY_PORT}"

        echo -e "\n${C_GRN}[V] Настройки успешно сохранены!${C_RST}"; sleep 1
    else
        shopt -u nocasematch
        echo -e "\n${C_RED}[x] Ошибка: Неверный формат! Попробуйте снова.${C_RST}"; sleep 2
    fi
}

test_proxy() {
    clear
    echo -e "${C_CYA}=== ТЕСТ ПРОКСИ ===${C_RST}"
    if ! $PROXY_ENABLED; then echo -e "${C_RED}Прокси отключён.${C_RST}"; sleep 2; return; fi
    
    echo -e "${C_YEL}Подключение к google.com:80 через $PROXY_TYPE...${C_RST}"
    local out
    out=$(curl -s -w "\n%{time_connect}" -m 3 -x "$PROXY_STR" -I "http://google.com")
    if [ $? -eq 0 ]; then
        local ms=$(echo "$out" | tail -n1 | awk '{print int($1*1000)}')
        echo -e "${C_GRN}Соединение установлено за ${ms}мс! HTTP-запрос прошел.${C_RST}"
    else
        echo -e "${C_RED}ОШИБКА: Сервер недоступен.${C_RST}"
    fi
    echo -ne "\n${C_CYA}Нажмите любую клавишу...${C_RST}"; read -r -n 1 -s
}

worker() {
    local target=$1 row=$2
    local ip="FAILED" http="FAIL" t12="FAIL" t13="FAIL" lat="0ms" verdict="IP BLOCK" color="$C_RED"

    local px_args=""
    if $PROXY_ENABLED; then 
        px_args="-x $PROXY_STR"
        if [[ "$PROXY_TYPE" == "SOCKS5" ]]; then px_args="${px_args/socks5:\/\//socks5h:\/\/}"; fi
        ip="[ *PROXIED* ]"
        else
        ip=""
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
        
        if [ -z "$ip" ]; then echo "ERROR|FAIL|FAIL|FAIL|0ms|DNS ERROR|$C_RED" > "$TMP_DIR/$row.res"; return; fi
    fi

    local http_out
    http_out=$(curl -s -m 2 $px_args -I "http://$target" -A "curl/7.88.1" -w "\n%{time_total}" 2>&1)
    if [ $? -eq 0 ]; then
        http="OK"; lat=$(echo "$http_out" | tail -n1 | tr ',' '.' | awk '{v=int($1*1000); if(v==0) v=1; print v"ms"}')
    else
        if echo "$http_out" | grep -qi "timeout"; then http="DROP"; else http="ERR"; fi
    fi

    local t12_out
    t12_out=$(curl -k -s -m 3 $px_args -I "https://$target" --tls-max 1.2 2>&1)
    if [ $? -eq 0 ]; then t12="OK"
    elif echo "$t12_out" | grep -qi "reset"; then t12="RST"
    else t12="DRP"
    fi

    local t13_out
    t13_out=$(LC_ALL=C curl -k -s -m 3 $px_args -I "https://$target" --tlsv1.3 2>&1)
    if [ $? -eq 0 ]; then t13="OK"
    elif echo "$t13_out" | grep -qiE "unsupported|not supported|unknown option|unrecognized option|built-in"; then t13="N/A"
    elif echo "$t13_out" | grep -qi "reset"; then t13="RST"
    else t13="DRP"
    fi

    if [ "$http" == "OK" ]; then
        if [ "$t12" == "OK" ] && [ "$t13" == "OK" ]; then
            verdict="AVAILABLE"; color="$C_GRN"
        elif [ "$t12" == "OK" ] && [ "$t13" == "N/A" ]; then
            verdict="AVAILABLE"; color="$C_GRN"
        elif [ "$t12" == "N/A" ] && [ "$t13" == "OK" ]; then
            verdict="AVAILABLE"; color="$C_GRN"
        elif [ "$t12" == "OK" ] && { [ "$t13" == "RST" ] || [ "$t13" == "DRP" ]; }; then
            verdict="THROTTLED"; color="$C_YEL"
        elif [ "$t13" == "OK" ] && { [ "$t12" == "RST" ] || [ "$t12" == "DRP" ]; }; then
            verdict="THROTTLED"; color="$C_YEL"
        else
            verdict="DPI BLOCK"; color="$C_YEL"
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

FIRST_RUN=true
FRAMES=("[=   ]" "[ =  ]" "[  = ]" "[   =]" "[  = ]" "[ =  ]")
f=0
NAV_STR="[ READY ] [ENTER] START | [H] HELP | [P] PROXY | [T] TEST | [S] SAVE | [Q] QUIT"

while true; do
    if $FIRST_RUN; then
        get_network_info
        TARGETS=("${BASE_TARGETS[@]}" "${CDN_LIST[@]}")
        TARGETS=($(echo "${TARGETS[@]}" | tr ' ' '\n' | awk '!a[$0]++'))
        draw_ui
        UI_Y=$((12 + ${#TARGETS[@]} + 1))
        out_str 2 $UI_Y 121 "$NAV_STR" "$C_WHT"; flush_buffer
        FIRST_RUN=false
    fi

    read -t $READ_TIMEOUT -n 1 -s key
    READ_STATUS=$?

    if [[ "$key" == "q" || "$key" == "Q" || "$key" == $'\e' ]]; then break
    elif [[ "$key" == "h" || "$key" == "H" ]]; then show_help; draw_ui; out_str 2 $UI_Y 121 "$NAV_STR" "$C_WHT"; flush_buffer
    elif [[ "$key" == "p" || "$key" == "P" ]]; then show_proxy_menu; draw_ui; out_str 2 $UI_Y 121 "$NAV_STR" "$C_WHT"; flush_buffer
    elif [[ "$key" == "t" || "$key" == "T" ]]; then test_proxy; draw_ui; out_str 2 $UI_Y 121 "$NAV_STR" "$C_WHT"; flush_buffer
    elif [[ "$key" == "s" || "$key" == "S" ]]; then
        out_str 2 $UI_Y 121 "[ WAIT ] SAVING RESULTS TO FILE..." "$C_CYA"; flush_buffer
        LOG="YT-DPI_Report.txt"
        {
            echo "=== YT-DPI REPORT ==="
            echo "TIME: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "ISP:  $ISP ($LOC)"
            echo "DNS:  $DNS"
            if $PROXY_ENABLED; then echo "PROXY: $PROXY_TYPE $PROXY_HOST:$PROXY_PORT"; else echo "> PROXY: [ OFF ]"; fi
            echo "------------------------------------------------------------------------------------------"
            printf "%-38s %-16s %-6s %-8s %-8s %-6s %s\n" "TARGET DOMAIN" "IP ADDRESS" "HTTP" "TLS 1.2" "TLS 1.3" "LAT" "RESULT"
            echo "------------------------------------------------------------------------------------------"
            for i in "${!TARGETS[@]}"; do
                row=$((12 + i))
                if [ -f "$TMP_DIR/$row.res" ]; then
                    IFS='|' read -r ip http t12 t13 lat verdict color < "$TMP_DIR/$row.res"
                    if $PROXY_ENABLED; then ip="[ PROXIED ]"; fi
                    printf "%-38s %-16s %-6s %-8s %-8s %-6s %s\n" "${TARGETS[$i]}" "$ip" "$http" "$t12" "$t13" "$lat" "$verdict"
                fi
            done
        } > "$LOG"
        out_str 2 $UI_Y 121 "[ SUCCESS ] SAVED TO: $(pwd)/$LOG" "$C_GRN"; flush_buffer
        sleep 2; out_str 2 $UI_Y 121 "$NAV_STR" "$C_WHT"; flush_buffer
    
    elif [[ -z "$key" && $READ_STATUS -eq 0 ]]; then 
        STATS_CLEAN=0; STATS_BLOCKED=0; STATS_RST=0; STATS_ERR=0
        
        out_str 2 $UI_Y 121 "[ WAIT ] REFRESHING NETWORK STATE..." "$C_CYA"; flush_buffer
        get_network_info
        TARGETS=("${BASE_TARGETS[@]}" "$CDN")
        TARGETS=($(echo "${TARGETS[@]}" | tr ' ' '\n' | awk '!a[$0]++'))
        
        draw_ui; UI_Y=$((12 + ${#TARGETS[@]} + 1))
        out_str 2 $UI_Y 121 "[ BUSY ] SCANNING IN PROGRESS... PRESS [Q] TO ABORT" "$C_YEL"; flush_buffer
        
        rm -f "$TMP_DIR"/*.res
        JOB_STATE=()
        ACTIVE_JOBS=${#TARGETS[@]}
        
        for i in "${!TARGETS[@]}"; do
            row=$((12 + i))
            out_str $X_VER $row 30 "PREPARING..." "$C_GRY"
            JOB_STATE[$i]=1
            # --- ФИКС 2: Блокируем stdin для фоновых процессов ---
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
                    out_str $X_T12  $row 8 "$t12" "$t12col"
                    [ "$t13" == "OK" ] && t13col="$C_GRN" || t13col="$C_RED"
                    [ "$t13" == "N/A" ] && t13col="$C_GRY"
                    out_str $X_T13  $row 8 "$t13" "$t13col"
                    out_str $X_LAT  $row 6 "$lat" "$C_CYA"
                    out_str $X_VER  $row 30 "$verdict" "$color"
                    
                    JOB_STATE[$i]=0
                    ((ACTIVE_JOBS--))
                else
                    anim_idx=$(( (f + row) % 6 ))
                    out_str $X_VER $row 30 "SCANNING ${FRAMES[$anim_idx]}" "$C_CYA"
                    
                    if (( f % 4 == 0 )); then
                        if $PROXY_ENABLED; then
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
            out_str 2 $UI_Y 121 "[ ABORTED ] SCAN STOPPED. [ENTER] RESTART | [H] HELP | [P] PROXY | [T] TEST | [Q] QUIT" "$C_RED"
        else
            out_str 2 $UI_Y 121 "[ SUCCESS ] SCAN FINISHED. [ENTER] RESTART | [H] HELP | [P] PROXY | [S] SAVE | [Q] QUIT" "$C_GRN"
        fi
        flush_buffer
        while read -t 0.1 -n 1 -s; do : ; done
    fi
done