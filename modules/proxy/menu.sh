#!/bin/bash
# ============================================================ #
# ==          МОДУЛЬ ПРОКСИ — MTProto и другие               == #
# ============================================================ #
#  ( РОДИТЕЛЬ | КЛАВИША | НАЗВАНИЕ | ФУНКЦИЯ | ПОРЯДОК | ГРУППА | ОПИСАНИЕ )
# @menu.manifest
# @item( main | 8 | 📡 Установка и настройка MTProto ${C_YELLOW}(telemt)${C_RESET} | show_proxy_menu | 45 | 3 | Установка и управление MTProto прокси для Telegram. )
#
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1

readonly _TELEMT_BIN="/bin/telemt"
readonly _TELEMT_CONFIG="/etc/telemt/telemt.toml"
readonly _TELEMT_SERVICE="telemt.service"
readonly _TELEMT_API="http://127.0.0.1:9091"

# --- Детект ---

_telemt_installed() {
    [[ -f "$_TELEMT_BIN" ]] && [[ -f "$_TELEMT_CONFIG" ]]
}

_telemt_running() {
    systemctl is-active --quiet "$_TELEMT_SERVICE" 2>/dev/null
}

# --- Сканер доменов ---

_telemt_scan_domains() {
    info "Сканирую популярные .ru домены, ищу самый быстрый..."
    echo ""
    local _scan_domains=("travel.yandex.ru" "api-maps.yandex.ru" "ads.x5.ru" "api.perekrestok.ru" "1c.ru" "rutube.ru" "sberbank.ru" "ozon.ru" "eh.vk.com")
    local _best_domain="" _best_time=9999

    for _d in "${_scan_domains[@]}"; do
        local _ping_ms
        _ping_ms=$(curl -so /dev/null -w '%{time_connect}' --connect-timeout 3 "https://${_d}" 2>/dev/null)
        if [[ -n "$_ping_ms" && "$_ping_ms" != "0.000000" ]]; then
            local _ms
            _ms=$(echo "$_ping_ms * 1000" | bc 2>/dev/null | cut -d. -f1)
            _ms=${_ms:-9999}
            printf "  %-25s ${C_CYAN}%s ms${C_RESET}" "$_d" "$_ms"
            if [[ "$_ms" -lt "$_best_time" ]]; then
                _best_time=$_ms
                _best_domain=$_d
                printf "  ${C_GREEN}← лучший${C_RESET}"
            fi
            echo ""
        fi
    done
    echo ""
    echo "${_best_domain:-travel.yandex.ru}"
}

_telemt_choose_domain() {
    printf_menu_option "1" "travel.yandex.ru"
    printf_menu_option "2" "api-maps.yandex.ru"
    printf_menu_option "3" "ads.x5.ru"
    printf_menu_option "4" "api.perekrestok.ru"
    printf_menu_option "5" "1c.ru"
    printf_menu_option "s" "🔍 Сканировать (подобрать лучший)"
    printf_menu_option "m" "Ввести свой"
    echo ""

    local domain_choice
    domain_choice=$(safe_read "Выбери домен" "1") || return

    case "$domain_choice" in
        1) echo "travel.yandex.ru" ;;
        2) echo "api-maps.yandex.ru" ;;
        3) echo "ads.x5.ru" ;;
        4) echo "api.perekrestok.ru" ;;
        5) echo "1c.ru" ;;
        s|S) _telemt_scan_domains | tail -1 ;;
        m|M) ask_non_empty "Введи домен" ;;
        *) echo "travel.yandex.ru" ;;
    esac
}

# --- Тюнинг ядра (обязательный) ---

_telemt_apply_tuning() {
    info "Применяю тюнинг ядра для высокой нагрузки..."

    # sysctl.conf — лимиты файлов
    if ! grep -q "fs.file-max = 2097152" /etc/sysctl.conf 2>/dev/null; then
        cat >> /etc/sysctl.conf << 'EOF'
fs.file-max = 2097152
fs.nr_open = 2097152
EOF
    fi

    # Сетевой тюнинг
    cat > /etc/sysctl.d/99-telemt-highload.conf << 'SYSCTL_EOF'
# LumaxADM: telemt high-load tuning
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_syncookies = 1
net.ipv4.ip_local_port_range = 10000 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
SYSCTL_EOF

    sysctl -p >/dev/null 2>&1
    sysctl -p /etc/sysctl.d/99-telemt-highload.conf >/dev/null 2>&1
    ok "Sysctl тюнинг применён."

    # Ulimits
    if ! grep -q "LumaxADM telemt" /etc/security/limits.conf 2>/dev/null; then
        cat >> /etc/security/limits.conf << 'LIMITS_EOF'
# LumaxADM telemt high-load
* soft nofile 1048576
* hard nofile 1048576
LIMITS_EOF
        ok "Ulimits обновлены (1M открытых файлов)."
    fi
}

# --- Установка ---

_telemt_install() {
    clear
    menu_header "📡 Установка MTProto прокси (telemt)"

    if _telemt_installed; then
        warn "telemt уже установлен. Если хочешь переустановить — сначала удали."
        return
    fi

    info "Сейчас пройдём по шагам. Отвечай на вопросы, я всё настрою."
    echo ""
    print_separator "─" 60

    # --- Шаг 1: Порт telemt ---
    echo ""
    info "Шаг 1: Порт для telemt"
    printf_description "${C_GRAY}Если планируешь Self-Steal (Caddy на 443) — ставь 7443 или 8443.${C_RESET}"
    printf_description "${C_GRAY}Если без Caddy — ставь 443.${C_RESET}"
    local proxy_port
    proxy_port=$(safe_read "Порт прокси" "7443") || return
    if ! validate_port "$proxy_port"; then
        err "Некорректный порт."
        return
    fi

    # --- Шаг 2: Ad Tag ---
    echo ""
    info "Шаг 2: Ad Tag из бота @MTProxybot"
    printf_description "Зайди в Telegram → @MTProxybot → /newproxy"
    printf_description "Укажи IP и порт ${proxy_port}, бот выдаст ad_tag."
    printf_description "${C_GRAY}Можно пропустить и добавить позже.${C_RESET}"
    local ad_tag
    ad_tag=$(safe_read "Ad Tag (Enter — пропустить)" "") || return

    # --- Шаг 3: TLS домен ---
    echo ""
    info "Шаг 3: Домен для маскировки (TLS)"
    printf_description "Прокси маскируется под HTTPS-соединение к этому домену."
    echo ""
    local tls_domain
    tls_domain=$(_telemt_choose_domain) || return

    # --- Шаг 4: Self-Steal (Caddy) ---
    echo ""
    info "Шаг 4: Настройка Self-Steal через Caddy"
    printf_description "Caddy ставится на порт 443 и отдаёт фейковый сайт."
    printf_description "telemt маскируется через него — максимальная защита от DPI."
    echo ""
    local setup_caddy=0
    local caddy_domain=""
    if ask_yes_no "Настроить Self-Steal через Caddy?" "y"; then
        setup_caddy=1
        caddy_domain=$(ask_non_empty "Домен для Caddy (твой домен, направленный на этот сервер)") || return
    fi

    # --- Шаг 5: Генерация secret ---
    echo ""
    info "Шаг 5: Генерирую секрет..."
    local secret
    secret=$(openssl rand -hex 16)
    ok "Secret: ${C_CYAN}${secret}${C_RESET}"

    # --- Шаг 6: Имя пользователя ---
    echo ""
    local username
    username=$(safe_read "Имя пользователя" "telemt") || return

    # --- Подтверждение ---
    echo ""
    print_separator "═" 60
    printf "  ${C_BOLD}${C_YELLOW}📋 ПРОВЕРЬ НАСТРОЙКИ:${C_RESET}\n"
    print_separator "─" 60
    printf "  Порт telemt:  ${C_CYAN}${proxy_port}${C_RESET}\n"
    printf "  TLS домен:    ${C_CYAN}${tls_domain}${C_RESET}\n"
    printf "  Юзер:         ${C_CYAN}${username}${C_RESET}\n"
    printf "  Secret:        ${C_CYAN}${secret}${C_RESET}\n"
    if [[ -n "$ad_tag" ]]; then
        printf "  Ad Tag:        ${C_CYAN}${ad_tag}${C_RESET}\n"
    else
        printf "  Ad Tag:        ${C_GRAY}пропущен${C_RESET}\n"
    fi
    if [[ $setup_caddy -eq 1 ]]; then
        printf "  Self-Steal:    ${C_GREEN}Caddy на 443 (${caddy_domain})${C_RESET}\n"
    else
        printf "  Self-Steal:    ${C_GRAY}нет${C_RESET}\n"
    fi
    print_separator "═" 60
    echo ""

    if ! ask_yes_no "Всё верно? Погнали ставить?"; then
        info "Отмена."
        return
    fi

    # ================ УСТАНОВКА ================
    echo ""
    info "Устанавливаю зависимости..."
    run_cmd apt-get update -qq >/dev/null 2>&1
    run_cmd apt-get install -y curl build-essential libssl-dev zlib1g-dev net-tools jq -qq >/dev/null 2>&1
    ok "Зависимости установлены."

    # Скачиваем telemt
    info "Скачиваю telemt..."
    local arch libc
    arch=$(uname -m)
    libc=$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu)

    if wget -qO- "https://github.com/telemt/telemt/releases/latest/download/telemt-${arch}-linux-${libc}.tar.gz" | tar -xz -C /tmp/; then
        run_cmd mv /tmp/telemt "$_TELEMT_BIN"
        run_cmd chmod +x "$_TELEMT_BIN"
        ok "telemt установлен."
    else
        err "Не удалось скачать telemt."
        return 1
    fi

    # Конфиг
    info "Создаю конфиг..."
    run_cmd mkdir -p /etc/telemt

    local ad_tag_line=""
    if [[ -n "$ad_tag" ]]; then
        ad_tag_line="ad_tag = \"${ad_tag}\""
    else
        ad_tag_line="# ad_tag = \"получи_в_@MTProxybot\""
    fi

    # Self-Steal секция
    local censorship_extra=""
    if [[ $setup_caddy -eq 1 ]]; then
        censorship_extra="mask = true
mask_port = 443"
    fi

    cat > "$_TELEMT_CONFIG" << TELEMT_CONF
[general]
${ad_tag_line}
use_middle_proxy = true

[general.modes]
classic = false
secure = false
tls = true

[server]
port = ${proxy_port}
max_connections = 0

[server.api]
enabled = true

[censorship]
tls_domain = "${tls_domain}"
${censorship_extra}

[access.users]
${username} = "${secret}"
TELEMT_CONF
    ok "Конфиг создан."

    # Пользователь
    info "Создаю системного пользователя..."
    if ! id telemt &>/dev/null; then
        useradd -d /opt/telemt -m -r -U telemt
    fi
    run_cmd chown -R telemt:telemt /etc/telemt
    ok "Пользователь telemt создан."

    # Systemd
    info "Создаю systemd-сервис..."
    cat > /etc/systemd/system/telemt.service << 'SERVICE_EOF'
[Unit]
Description=Telemt
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=telemt
Group=telemt
WorkingDirectory=/opt/telemt
ExecStart=/bin/telemt /etc/telemt/telemt.toml
Restart=on-failure
LimitNOFILE=1048576
LimitNPROC=65535
TasksMax=infinity
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
SERVICE_EOF
    ok "Сервис создан."

    # Тюнинг (обязательный)
    _telemt_apply_tuning

    # Self-Steal: Caddy
    if [[ $setup_caddy -eq 1 ]]; then
        info "Устанавливаю Caddy..."
        run_cmd apt-get install -y caddy -qq >/dev/null 2>&1

        info "Скачиваю фейковый сайт-заглушку..."
        run_cmd mkdir -p /var/www/fake
        if git clone --quiet https://github.com/Famebloody/SNI-Templates.git /var/www/fake 2>/dev/null; then
            run_cmd chmod -R 775 /var/www/fake
            ok "Сайт-заглушка установлена."
        else
            warn "Не удалось скачать шаблон. Caddy будет отдавать пустую страницу."
            run_cmd mkdir -p /var/www/fake/downloader
            echo "<html><body>Welcome</body></html>" > /var/www/fake/downloader/index.html
        fi

        info "Настраиваю Caddy..."
        cat > /etc/caddy/Caddyfile << CADDY_CONF
${caddy_domain}:443 {
    root * /var/www/fake/downloader
    try_files {path} /index.html
    file_server

    log {
        output file /var/log/caddy/access.log
    }
}
CADDY_CONF
        run_cmd mkdir -p /var/log/caddy
        run_cmd systemctl restart caddy
        if systemctl is-active --quiet caddy; then
            ok "Caddy запущен на 443 с доменом ${caddy_domain}"
        else
            warn "Caddy не запустился. Проверь: journalctl -u caddy -n 20"
        fi
    fi

    # Открываем порт
    if command -v ufw &>/dev/null; then
        info "Открываю порт ${proxy_port}/tcp в UFW..."
        run_cmd ufw allow "${proxy_port}"/tcp comment 'MTProto telemt'
        if [[ $setup_caddy -eq 1 ]]; then
            run_cmd ufw allow 443/tcp comment 'Caddy HTTPS'
            run_cmd ufw allow 80/tcp comment 'Caddy HTTP (ACME)'
        fi
        ok "Порты открыты."
    fi

    # Запуск
    info "Запускаю telemt..."
    run_cmd systemctl daemon-reload
    run_cmd systemctl enable telemt.service >/dev/null 2>&1
    run_cmd systemctl restart telemt.service

    info "Жду инициализации (STUN + DC connect)..."
    sleep 10

    if _telemt_running; then
        ok "telemt запущен и работает!"
        echo ""

        info "Получаю ссылку..."
        local link_data
        link_data=$(curl -s "${_TELEMT_API}/v1/users" 2>/dev/null)
        if [[ -n "$link_data" ]]; then
            local tls_link
            tls_link=$(echo "$link_data" | jq -r '.data[0].links.tls // .data[0].links.tls[0] // empty' 2>/dev/null)
            # Если массив
            if [[ -z "$tls_link" || "$tls_link" == "null" ]]; then
                tls_link=$(echo "$link_data" | jq -r '.data[0].links.tls[0] // empty' 2>/dev/null)
            fi
            if [[ -n "$tls_link" && "$tls_link" != "null" ]]; then
                echo ""
                print_separator "═" 60
                printf "  ${C_BOLD}${C_GREEN}🔗 ССЫЛКА ДЛЯ TELEGRAM:${C_RESET}\n"
                print_separator "─" 60
                echo ""
                printf "  ${C_CYAN}${tls_link}${C_RESET}\n"
                echo ""
                print_separator "═" 60
                echo ""
                info "Скопируй → Telegram → Настройки → Прокси → Добавить."
            else
                info "Ссылка ещё не сгенерирована. Получи через пункт [1] в меню."
            fi
        fi
    else
        err "Сервис не запустился. Смотри логи:"
        printf_description "journalctl -u telemt -n 30"
    fi
}

# --- Управление ---

_telemt_show_status() {
    print_separator "─" 60
    info "Статус telemt"

    if _telemt_running; then
        printf_description "Сервис: ${C_GREEN}работает${C_RESET}"
    else
        printf_description "Сервис: ${C_RED}остановлен${C_RESET}"
    fi

    local port
    port=$(grep "^port" "$_TELEMT_CONFIG" 2>/dev/null | grep -oE '[0-9]+' | head -1)
    printf_description "Порт: ${C_CYAN}${port:-?}${C_RESET}"

    local domain
    domain=$(grep "tls_domain" "$_TELEMT_CONFIG" 2>/dev/null | cut -d'"' -f2)
    printf_description "TLS домен: ${C_CYAN}${domain:-?}${C_RESET}"

    # Caddy/Self-Steal
    if systemctl is-active --quiet caddy 2>/dev/null; then
        printf_description "Self-Steal: ${C_GREEN}Caddy активен на 443${C_RESET}"
    fi

    if _telemt_running; then
        local api_data
        api_data=$(curl -s --connect-timeout 2 "${_TELEMT_API}/v1/users" 2>/dev/null)
        if [[ -n "$api_data" ]] && command -v jq &>/dev/null; then
            local conns active_ips recent_ips
            conns=$(echo "$api_data" | jq -r '[.data[].current_connections] | add // 0' 2>/dev/null)
            active_ips=$(echo "$api_data" | jq -r '[.data[].active_unique_ips] | add // 0' 2>/dev/null)
            recent_ips=$(echo "$api_data" | jq -r '[.data[].recent_unique_ips] | add // 0' 2>/dev/null)
            printf_description "Подключений: ${C_CYAN}${conns}${C_RESET} | Уникальных IP: ${C_CYAN}${active_ips}${C_RESET} (за час: ${recent_ips})"
        fi

        local cpu_cores ram_mb
        cpu_cores=$(nproc 2>/dev/null || echo 1)
        ram_mb=$(free -m 2>/dev/null | awk '/^Mem:/ {print $2}')
        local max_estimate=$(( cpu_cores * 2500 ))
        if [[ "${ram_mb:-0}" -lt 1024 ]]; then
            max_estimate=$(( max_estimate > 2000 ? 2000 : max_estimate ))
        fi
        printf_description "Потолок: ${C_YELLOW}~${max_estimate}${C_RESET} подключений ${C_GRAY}(${cpu_cores} CPU, ${ram_mb}MB RAM)${C_RESET}"
    fi
    print_separator "─" 60
}

_telemt_get_link() {
    clear
    menu_header "🔗 Ссылка для подключения"

    if ! _telemt_running; then
        err "telemt не запущен."
        return
    fi

    ensure_dependencies "jq"

    local api_data
    api_data=$(curl -s --connect-timeout 3 "${_TELEMT_API}/v1/users" 2>/dev/null)

    if [[ -z "$api_data" ]]; then
        err "Не удалось получить данные из API."
        return
    fi

    local conns active_ips
    conns=$(echo "$api_data" | jq -r '[.data[].current_connections] | add // 0' 2>/dev/null)
    active_ips=$(echo "$api_data" | jq -r '[.data[].active_unique_ips] | add // 0' 2>/dev/null)

    local tls_link
    tls_link=$(echo "$api_data" | jq -r '.data[0].links.tls // empty' 2>/dev/null)
    if [[ "$tls_link" == "["* ]]; then
        tls_link=$(echo "$api_data" | jq -r '.data[0].links.tls[0] // empty' 2>/dev/null)
    fi

    local display_ip
    display_ip=$(echo "$tls_link" | grep -oE 'server=[^&]+' | cut -d= -f2)

    local port
    port=$(grep "^port" "$_TELEMT_CONFIG" 2>/dev/null | grep -oE '[0-9]+' | head -1)

    echo ""
    printf "  ${C_GRAY}IP сервера:${C_RESET}    ${C_WHITE}${display_ip:-?}${C_RESET}\n"
    printf "  ${C_GRAY}Порт:${C_RESET}          ${C_WHITE}${port:-?}${C_RESET}\n"
    printf "  ${C_GRAY}Подключений:${C_RESET}   ${C_CYAN}${conns}${C_RESET}\n"
    printf "  ${C_GRAY}Уникальных IP:${C_RESET} ${C_CYAN}${active_ips}${C_RESET}\n"
    echo ""

    if [[ -n "$tls_link" && "$tls_link" != "null" ]]; then
        print_separator "═" 60
        printf "  ${C_BOLD}${C_GREEN}🔗 ССЫЛКА ДЛЯ TELEGRAM:${C_RESET}\n"
        print_separator "─" 60
        echo ""
        printf "  ${C_CYAN}${tls_link}${C_RESET}\n"
        echo ""
        print_separator "═" 60
        echo ""
        info "Скопируй → Telegram → Настройки → Прокси → Добавить."
    else
        err "Ссылка не сгенерирована. Проверь логи: journalctl -u telemt -n 20"
    fi
}

_telemt_change_domain() {
    clear
    menu_header "🌐 Смена домена маскировки"

    local current_domain
    current_domain=$(grep "tls_domain" "$_TELEMT_CONFIG" 2>/dev/null | cut -d'"' -f2)
    printf_description "Текущий: ${C_CYAN}${current_domain:-не задан}${C_RESET}"
    echo ""

    local new_domain
    new_domain=$(_telemt_choose_domain) || return

    if [[ "$new_domain" == "$current_domain" ]]; then
        info "Домен не изменился."
        return
    fi

    run_cmd sed -i "s|tls_domain = \".*\"|tls_domain = \"${new_domain}\"|" "$_TELEMT_CONFIG"
    ok "Домен: ${new_domain}"

    info "Перезапускаю..."
    run_cmd systemctl restart telemt.service
    sleep 3
    _telemt_running && ok "Готово." || err "Сервис не запустился."
    warn "Старые ссылки больше не работают! Получи новую через [1]."
}

_telemt_change_ad_tag() {
    clear
    menu_header "🏷️ Изменение Ad Tag"

    local current_tag
    current_tag=$(grep "^ad_tag" "$_TELEMT_CONFIG" 2>/dev/null | cut -d'"' -f2)
    if [[ -n "$current_tag" ]]; then
        printf_description "Текущий: ${C_CYAN}${current_tag}${C_RESET}"
    else
        printf_description "Ad Tag: ${C_RED}не задан${C_RESET}"
    fi
    echo ""
    info "Получить: Telegram → @MTProxybot → /newproxy"
    echo ""

    local new_tag
    new_tag=$(safe_read "Новый Ad Tag (Enter — оставить)" "") || return
    if [[ -z "$new_tag" ]]; then
        info "Без изменений."
        return
    fi

    if grep -q "^# ad_tag" "$_TELEMT_CONFIG"; then
        run_cmd sed -i "s|^# ad_tag.*|ad_tag = \"${new_tag}\"|" "$_TELEMT_CONFIG"
    elif grep -q "^ad_tag" "$_TELEMT_CONFIG"; then
        run_cmd sed -i "s|^ad_tag = \".*\"|ad_tag = \"${new_tag}\"|" "$_TELEMT_CONFIG"
    else
        run_cmd sed -i "/^\[general\]/a ad_tag = \"${new_tag}\"" "$_TELEMT_CONFIG"
    fi
    ok "Ad Tag обновлён."

    info "Перезапускаю..."
    run_cmd systemctl restart telemt.service
    sleep 3
    _telemt_running && ok "Готово." || err "Сервис не запустился."
}

_telemt_edit_config() {
    local editor="${EDITOR:-nano}"
    "$editor" "$_TELEMT_CONFIG"
    echo ""
    if ask_yes_no "Перезапустить telemt?"; then
        run_cmd systemctl restart telemt.service
        sleep 3
        _telemt_running && ok "Перезапущен." || err "Сервис не запустился."
    fi
}

_telemt_update() {
    clear
    menu_header "⬆️ Обновление telemt"

    local current_ver
    current_ver=$("$_TELEMT_BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    printf_description "Текущая: ${C_CYAN}${current_ver:-?}${C_RESET}"

    info "Проверяю последнюю версию..."
    local latest_ver
    latest_ver=$(curl -s --connect-timeout 5 "https://api.github.com/repos/telemt/telemt/releases/latest" 2>/dev/null \
        | grep '"tag_name"' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

    if [[ -n "$latest_ver" ]]; then
        printf_description "Последняя: ${C_GREEN}${latest_ver}${C_RESET}"
        if [[ "$current_ver" == "$latest_ver" ]]; then
            ok "Уже последняя версия."
            return
        fi
    fi
    echo ""
    if ! ask_yes_no "Обновить?"; then return; fi

    local arch libc
    arch=$(uname -m)
    libc=$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu)

    info "Скачиваю..."
    if wget -qO- "https://github.com/telemt/telemt/releases/latest/download/telemt-${arch}-linux-${libc}.tar.gz" | tar -xz -C /tmp/; then
        run_cmd systemctl stop telemt.service 2>/dev/null || true
        run_cmd mv /tmp/telemt "$_TELEMT_BIN"
        run_cmd chmod +x "$_TELEMT_BIN"
        run_cmd systemctl start telemt.service
        sleep 3
        local new_ver
        new_ver=$("$_TELEMT_BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        ok "Обновлён до ${new_ver:-latest}!"
    else
        err "Не удалось скачать."
    fi
}

_telemt_uninstall() {
    clear
    menu_header "🗑️ Удаление telemt"

    if ! ask_yes_no "Точно удалить? Сервис, конфиг и бинарник будут снесены"; then
        info "Отмена."
        return
    fi

    run_cmd systemctl stop telemt.service 2>/dev/null || true
    run_cmd systemctl disable telemt.service 2>/dev/null || true
    run_cmd rm -f /etc/systemd/system/telemt.service
    run_cmd systemctl daemon-reload
    run_cmd rm -f "$_TELEMT_BIN"
    run_cmd rm -rf /etc/telemt
    userdel telemt 2>/dev/null || true
    run_cmd rm -rf /opt/telemt
    run_cmd rm -f /etc/sysctl.d/99-telemt-highload.conf
    sysctl --system >/dev/null 2>&1

    ok "telemt полностью удалён."
}

_telemt_manage_menu() {
    enable_graceful_ctrlc
    while true; do
        clear
        menu_header "📡 Управление MTProto прокси (telemt)"

        _telemt_show_status
        echo ""

        printf_menu_option "1" "🔗 Получить ссылку для подключения"
        echo ""
        printf_menu_option "2" "▶️  Запустить"
        printf_menu_option "3" "⏹️  Остановить"
        printf_menu_option "4" "🔄 Перезапустить"
        echo ""
        printf_menu_option "5" "🌐 Сменить домен маскировки"
        printf_menu_option "6" "🏷️  Изменить Ad Tag"
        printf_menu_option "7" "⬆️  Обновить telemt"
        printf_menu_option "e" "📝 Редактировать конфиг"
        echo ""
        printf_menu_option "d" "🗑️  Удалить telemt ${C_RED}(полностью)${C_RESET}"
        echo ""
        printf_menu_option "b" "Назад"
        echo ""

        local choice
        choice=$(safe_read "Выбирай" "") || break

        case "$choice" in
            1) _telemt_get_link; wait_for_enter ;;
            2)
                info "Запускаю..."
                run_cmd systemctl start telemt.service
                sleep 3
                _telemt_running && ok "Запущен." || err "Не запустился."
                wait_for_enter
                ;;
            3)
                run_cmd systemctl stop telemt.service
                ok "Остановлен."
                wait_for_enter
                ;;
            4)
                run_cmd systemctl restart telemt.service
                sleep 3
                _telemt_running && ok "Перезапущен." || err "Не запустился."
                wait_for_enter
                ;;
            5) _telemt_change_domain; wait_for_enter ;;
            6) _telemt_change_ad_tag; wait_for_enter ;;
            7) _telemt_update; wait_for_enter ;;
            e|E) _telemt_edit_config; wait_for_enter ;;
            d|D)
                _telemt_uninstall
                wait_for_enter
                break
                ;;
            b|B) break ;;
            *) warn "Нет такого пункта." && sleep 1 ;;
        esac
    done
    disable_graceful_ctrlc
}

# --- Главное меню ---

show_proxy_menu() {
    enable_graceful_ctrlc
    while true; do
        clear
        menu_header "📡 Прокси для Telegram"
        printf_description "Установка и управление MTProto прокси."
        echo ""

        if _telemt_installed; then
            printf_menu_option "1" "⚙️  Управление MTProto прокси ${C_GREEN}(telemt)${C_RESET}"
        else
            printf_menu_option "1" "📦 Установить MTProto прокси ${C_YELLOW}(telemt)${C_RESET}"
        fi

        echo ""
        printf_menu_option "b" "Назад"
        echo ""

        local choice
        choice=$(safe_read "Выбирай" "") || break

        case "$choice" in
            1)
                if _telemt_installed; then
                    _telemt_manage_menu
                else
                    _telemt_install
                    wait_for_enter
                fi
                ;;
            b|B) break ;;
            *) warn "Нет такого пункта." && sleep 1 ;;
        esac
    done
    disable_graceful_ctrlc
}
