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

    # --- Шаг 1: Порт ---
    echo ""
    info "Шаг 1: На каком порту будет работать прокси?"
    printf_description "${C_GRAY}443 — стандарт HTTPS, лучшая маскировка. 8443 — если 443 занят.${C_RESET}"
    local proxy_port
    proxy_port=$(safe_read "Порт прокси" "443") || return
    if ! validate_port "$proxy_port"; then
        err "Некорректный порт."
        return
    fi

    # --- Шаг 2: Ad Tag ---
    echo ""
    info "Шаг 2: Ad Tag из бота @MTProxybot"
    printf_description "Зайди в Telegram → @MTProxybot → /newproxy"
    printf_description "Укажи IP сервера и порт ${proxy_port}, бот выдаст ad_tag."
    printf_description "${C_GRAY}Если пока нет — можешь оставить пустым и добавить потом.${C_RESET}"
    local ad_tag
    ad_tag=$(safe_read "Ad Tag (или Enter чтобы пропустить)" "") || return

    # --- Шаг 3: TLS домен ---
    echo ""
    info "Шаг 3: Домен для маскировки (TLS)"
    printf_description "Прокси маскируется под HTTPS-соединение к этому домену."
    printf_description "${C_GRAY}Идеально — .ru сайт, чей CDN близко к твоему серверу.${C_RESET}"
    echo ""
    printf_menu_option "1" "travel.yandex.ru"
    printf_menu_option "2" "api-maps.yandex.ru"
    printf_menu_option "3" "ads.x5.ru"
    printf_menu_option "4" "api.perekrestok.ru"
    printf_menu_option "5" "1c.ru"
    printf_menu_option "s" "🔍 Сканировать домены (подобрать лучший)"
    printf_menu_option "m" "Ввести свой"
    echo ""

    local domain_choice
    domain_choice=$(safe_read "Выбери домен" "1") || return

    local tls_domain
    case "$domain_choice" in
        1) tls_domain="travel.yandex.ru" ;;
        2) tls_domain="api-maps.yandex.ru" ;;
        3) tls_domain="ads.x5.ru" ;;
        4) tls_domain="api.perekrestok.ru" ;;
        5) tls_domain="1c.ru" ;;
        s|S)
            echo ""
            info "Сканирую популярные .ru домены, ищу самый быстрый..."
            echo ""
            local _scan_domains=("travel.yandex.ru" "api-maps.yandex.ru" "ads.x5.ru" "api.perekrestok.ru" "1c.ru" "rutube.ru" "max.ru" "sberbank.ru" "ozon.ru" "eh.vk.com")
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
                else
                    printf "  %-25s ${C_RED}недоступен${C_RESET}\n" "$_d"
                fi
            done

            echo ""
            if [[ -n "$_best_domain" ]]; then
                ok "Лучший домен: ${_best_domain} (${_best_time} ms)"
                tls_domain="$_best_domain"
                local custom_domain
                custom_domain=$(safe_read "Использовать ${_best_domain}? (Enter) или введи свой" "$_best_domain") || return
                tls_domain="$custom_domain"
            else
                warn "Ни один домен не ответил. Ставлю дефолт."
                tls_domain="travel.yandex.ru"
            fi
            ;;
        m|M) tls_domain=$(ask_non_empty "Введи домен") || return ;;
        *) tls_domain="travel.yandex.ru" ;;
    esac

    # --- Шаг 4: Генерация secret ---
    echo ""
    info "Шаг 4: Генерирую секрет..."
    local secret
    secret=$(openssl rand -hex 16)
    ok "Secret: ${C_CYAN}${secret}${C_RESET}"

    # --- Шаг 5: Имя пользователя ---
    echo ""
    local username
    username=$(safe_read "Имя пользователя для прокси" "user") || return

    # --- Подтверждение ---
    echo ""
    print_separator "═" 60
    printf "  ${C_BOLD}${C_YELLOW}📋 ПРОВЕРЬ НАСТРОЙКИ:${C_RESET}\n"
    print_separator "─" 60
    printf "  Порт:     ${C_CYAN}${proxy_port}${C_RESET}\n"
    printf "  TLS:      ${C_CYAN}${tls_domain}${C_RESET}\n"
    printf "  Юзер:     ${C_CYAN}${username}${C_RESET}\n"
    printf "  Secret:   ${C_CYAN}${secret}${C_RESET}\n"
    if [[ -n "$ad_tag" ]]; then
        printf "  Ad Tag:   ${C_CYAN}${ad_tag}${C_RESET}\n"
    else
        printf "  Ad Tag:   ${C_GRAY}не задан (можно добавить позже)${C_RESET}\n"
    fi
    print_separator "═" 60
    echo ""

    if ! ask_yes_no "Всё верно? Погнали ставить?"; then
        info "Отмена. Ничего не тронуто."
        return
    fi

    # === УСТАНОВКА ===
    echo ""
    info "Устанавливаю зависимости..."
    run_cmd apt-get update -qq >/dev/null 2>&1
    run_cmd apt-get install -y curl build-essential libssl-dev zlib1g-dev net-tools -qq >/dev/null 2>&1
    ok "Зависимости установлены."

    info "Скачиваю telemt..."
    local arch
    arch=$(uname -m)
    local libc
    libc=$(ldd --version 2>&1 | grep -iq musl && echo musl || echo gnu)

    if wget -qO- "https://github.com/telemt/telemt/releases/latest/download/telemt-${arch}-linux-${libc}.tar.gz" | tar -xz -C /tmp/; then
        run_cmd mv /tmp/telemt "$_TELEMT_BIN"
        run_cmd chmod +x "$_TELEMT_BIN"
        ok "Бинарник установлен."
    else
        err "Не удалось скачать telemt."
        return 1
    fi

    info "Создаю конфиг..."
    run_cmd mkdir -p /etc/telemt

    local ad_tag_line=""
    if [[ -n "$ad_tag" ]]; then
        ad_tag_line="ad_tag = \"${ad_tag}\""
    else
        ad_tag_line="# ad_tag = \"получи_в_@MTProxybot\""
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
max_connections = 10000

[server.api]
enabled = true
# listen = "127.0.0.1:9091"
# whitelist = ["127.0.0.1/32"]
# read_only = true

[censorship]
tls_domain = "${tls_domain}"

[access.users]
${username} = "${secret}"
TELEMT_CONF
    ok "Конфиг создан: ${_TELEMT_CONFIG}"

    info "Создаю системного пользователя..."
    if ! id telemt &>/dev/null; then
        useradd -d /opt/telemt -m -r -U telemt
    fi
    run_cmd chown -R telemt:telemt /etc/telemt
    ok "Пользователь telemt создан."

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

    # High-load тюнинг ядра
    info "Применяю тюнинг для высокой нагрузки..."
    cat > /etc/sysctl.d/99-telemt-highload.conf << 'SYSCTL_EOF'
# LumaxADM: telemt high-load tuning
fs.file-max = 2097152
fs.nr_open = 2097152
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 10000 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
SYSCTL_EOF
    sysctl --system >/dev/null 2>&1
    ok "Sysctl тюнинг применён (макс. файлов, TCP backlog, буферы)."

    # Ulimits
    if ! grep -q "LumaxADM telemt" /etc/security/limits.conf 2>/dev/null; then
        cat >> /etc/security/limits.conf << 'LIMITS_EOF'
# LumaxADM telemt high-load
* soft nofile 1048576
* hard nofile 1048576
LIMITS_EOF
        ok "Ulimits обновлены (1M открытых файлов)."
    fi

    # Открываем порт
    if command -v ufw &>/dev/null; then
        info "Открываю порт ${proxy_port}/tcp в UFW..."
        run_cmd ufw allow "${proxy_port}"/tcp comment 'MTProto telemt'
        ok "Порт открыт."
    fi

    info "Запускаю telemt..."
    run_cmd systemctl daemon-reload
    run_cmd systemctl enable telemt.service >/dev/null 2>&1
    run_cmd systemctl restart telemt.service
    sleep 2

    if _telemt_running; then
        ok "telemt запущен и работает!"
        echo ""

        # Получаем ссылку
        info "Получаю ссылку для подключения..."
        sleep 1
        local link_data
        link_data=$(curl -s "${_TELEMT_API}/v1/users" 2>/dev/null)
        if [[ -n "$link_data" ]] && command -v jq &>/dev/null; then
            local tls_link
            tls_link=$(echo "$link_data" | jq -r '.data[0].links.tls // empty' 2>/dev/null)
            if [[ -n "$tls_link" ]]; then
                echo ""
                print_separator "═" 60
                printf "  ${C_BOLD}${C_GREEN}🔗 ССЫЛКА ДЛЯ ПОДКЛЮЧЕНИЯ:${C_RESET}\n"
                print_separator "─" 60
                printf "  ${C_CYAN}${tls_link}${C_RESET}\n"
                print_separator "═" 60
            fi
        else
            info "Ссылку можно получить командой:"
            printf_description "curl -s ${_TELEMT_API}/v1/users | jq"
        fi
    else
        err "Сервис не запустился. Проверь логи:"
        printf_description "journalctl -u telemt -n 20"
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

    # Порт из конфига
    local port
    port=$(grep "^port" "$_TELEMT_CONFIG" 2>/dev/null | grep -oE '[0-9]+' | head -1)
    printf_description "Порт: ${C_CYAN}${port:-?}${C_RESET}"

    # TLS домен
    local domain
    domain=$(grep "tls_domain" "$_TELEMT_CONFIG" 2>/dev/null | cut -d'"' -f2)
    printf_description "TLS домен: ${C_CYAN}${domain:-?}${C_RESET}"

    # Статистика из API
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

        # Оценка нагрузки
        local cpu_cores
        cpu_cores=$(nproc 2>/dev/null || echo 1)
        local ram_mb
        ram_mb=$(free -m 2>/dev/null | awk '/^Mem:/ {print $2}')
        local max_estimate=$(( cpu_cores * 2500 ))
        if [[ "${ram_mb:-0}" -lt 1024 ]]; then
            max_estimate=$(( max_estimate > 2000 ? 2000 : max_estimate ))
        fi
        printf_description "Потолок сервера: ${C_YELLOW}~${max_estimate}${C_RESET} одновременных подключений ${C_GRAY}(${cpu_cores} CPU, ${ram_mb}MB RAM)${C_RESET}"
    fi
    print_separator "─" 60
}

_telemt_get_link() {
    clear
    menu_header "🔗 Ссылка для подключения"

    if ! _telemt_running; then
        err "telemt не запущен. Сначала запусти."
        return
    fi

    ensure_dependencies "jq"

    local link_data
    link_data=$(curl -s "${_TELEMT_API}/v1/users" 2>/dev/null)

    if [[ -z "$link_data" ]]; then
        err "Не удалось получить данные из API. Проверь что API включён в конфиге."
        return
    fi

    echo ""
    echo "$link_data" | jq -r '.data[] | "  Юзер: \(.name // "unknown")\n  Подключений: \(.current_connections)\n  Уникальных IP: \(.active_unique_ips)\n  TLS ссылка:\n  \(.links.tls // "нет")\n"' 2>/dev/null

    echo ""
    print_separator "─" 60
    info "Скопируй TLS ссылку и вставь в настройки Telegram → Прокси."
}

_telemt_add_user() {
    clear
    menu_header "👤 Добавить пользователя"

    local username
    username=$(ask_non_empty "Имя нового пользователя") || return

    local secret
    secret=$(openssl rand -hex 16)

    # Добавляем в конфиг
    if grep -q "^\[access\.users\]" "$_TELEMT_CONFIG"; then
        run_cmd sed -i "/^\[access\.users\]/a ${username} = \"${secret}\"" "$_TELEMT_CONFIG"
    else
        echo -e "\n[access.users]\n${username} = \"${secret}\"" | run_cmd tee -a "$_TELEMT_CONFIG" >/dev/null
    fi

    ok "Пользователь ${username} добавлен."
    info "Secret: ${C_CYAN}${secret}${C_RESET}"
    echo ""

    info "Перезапускаю telemt..."
    run_cmd systemctl restart telemt.service
    sleep 2

    if _telemt_running; then
        ok "Перезапущен. Новый юзер активен."
    else
        err "Сервис не запустился после изменения конфига."
    fi
}

_telemt_edit_config() {
    local editor="${EDITOR:-nano}"
    "$editor" "$_TELEMT_CONFIG"
    echo ""
    if ask_yes_no "Перезапустить telemt чтобы применить изменения?"; then
        run_cmd systemctl restart telemt.service
        sleep 2
        if _telemt_running; then
            ok "Перезапущен."
        else
            err "Сервис не запустился. Проверь конфиг на ошибки."
        fi
    fi
}

_telemt_uninstall() {
    clear
    menu_header "🗑️ Удаление telemt"

    if ! ask_yes_no "Точно удалить MTProto прокси? Будет снесён сервис, конфиг и бинарник"; then
        info "Отмена."
        return
    fi

    info "Останавливаю сервис..."
    run_cmd systemctl stop telemt.service 2>/dev/null || true
    run_cmd systemctl disable telemt.service 2>/dev/null || true
    run_cmd rm -f /etc/systemd/system/telemt.service
    run_cmd systemctl daemon-reload

    info "Удаляю файлы..."
    run_cmd rm -f "$_TELEMT_BIN"
    run_cmd rm -rf /etc/telemt

    info "Удаляю пользователя..."
    userdel telemt 2>/dev/null || true
    run_cmd rm -rf /opt/telemt

    ok "telemt полностью удалён. Чистенько."
}

_telemt_manage_menu() {
    enable_graceful_ctrlc
    while true; do
        clear
        menu_header "📡 Управление MTProto прокси (telemt)"

        _telemt_show_status
        echo ""

        printf_menu_option "1" "🔗 Получить ссылку для подключения"
        printf_menu_option "2" "👤 Добавить пользователя"
        echo ""
        printf_menu_option "3" "▶️  Запустить"
        printf_menu_option "4" "⏹️  Остановить"
        printf_menu_option "5" "🔄 Перезапустить"
        echo ""
        printf_menu_option "e" "📝 Редактировать конфиг"
        printf_menu_option "d" "🗑️  Удалить telemt ${C_RED}(полностью)${C_RESET}"
        echo ""
        printf_menu_option "b" "Назад"
        echo ""

        local choice
        choice=$(safe_read "Выбирай" "") || break

        case "$choice" in
            1) _telemt_get_link; wait_for_enter ;;
            2) _telemt_add_user; wait_for_enter ;;
            3)
                info "Запускаю telemt..."
                run_cmd systemctl start telemt.service
                sleep 2
                _telemt_running && ok "Запущен." || err "Не удалось запустить."
                wait_for_enter
                ;;
            4)
                info "Останавливаю telemt..."
                run_cmd systemctl stop telemt.service
                ok "Остановлен."
                wait_for_enter
                ;;
            5)
                info "Перезапускаю telemt..."
                run_cmd systemctl restart telemt.service
                sleep 2
                _telemt_running && ok "Перезапущен." || err "Не удалось перезапустить."
                wait_for_enter
                ;;
            e|E) _telemt_edit_config; wait_for_enter ;;
            d|D)
                _telemt_uninstall
                wait_for_enter
                break  # Выходим из меню управления после удаления
                ;;
            b|B) break ;;
            *) warn "Нет такого пункта." && sleep 1 ;;
        esac
    done
    disable_graceful_ctrlc
}

# --- Главное меню раздела ---

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
