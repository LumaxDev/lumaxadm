#!/bin/bash
# ============================================================ #
# ==             REMNAWAVE: УПРАВЛЕНИЕ ПАНЕЛЬЮ И НОДОЙ       == #
# ============================================================ #
#  ( РОДИТЕЛЬ | КЛАВИША | НАЗВАНИЕ | ФУНКЦИЯ | ПОРЯДОК | ГРУППА | ОПИСАНИЕ )
# @menu.manifest
# @item( main | 7 | 💿 Remnawave ${C_YELLOW}(Панель, Нода, SelfSteal, WARP)${C_RESET} | show_remnawave_centre_menu | 40 | 3 | Установка и управление панелью Remnawave и нодами. )
#
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1 # Защита от прямого запуска

# --- Детект ---

_remna_panel_installed() {
    command -v docker &>/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^remnawave$"
}

_remna_node_installed() {
    command -v docker &>/dev/null && docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^remnanode"
}

_remna_panel_script_installed() {
    command -v remnawave &>/dev/null
}

_remna_node_script_installed() {
    command -v remnanode &>/dev/null
}

_remna_selfsteal_installed() {
    command -v selfsteal &>/dev/null
}

_remna_warp_installed() {
    command -v wtm &>/dev/null
}

# --- Действия ---

_remna_install_panel_script() {
    clear
    menu_header "💿 Установка скрипта управления панелью"
    info "Ставлю скрипт от Dignezzz... Сейчас всё будет."
    echo ""
    curl -Ls https://github.com/DigneZzZ/remnawave-scripts/raw/main/remnawave.sh -o /tmp/_lumaxadm_rw.sh && bash /tmp/_lumaxadm_rw.sh @ install-script --name remnawave; rm -f /tmp/_lumaxadm_rw.sh
    local exit_code=$?
    echo ""
    if [[ $exit_code -eq 0 ]] && command -v remnawave &>/dev/null; then
        ok "Скрипт управления панелью установлен!"
        info "Запустить можно командой: ${C_CYAN}remnawave${C_RESET}"
    else
        err "Что-то пошло не так при установке."
    fi
}

_remna_run_panel_script() {
    clear
    menu_header "💿 Скрипт управления панелью"
    info "Запускаю скрипт от Dignezzz..."
    echo ""
    remnawave
}

_remna_install_node() {
    clear
    menu_header "📡 Установка Remnanode"

    info "Для установки ноды нужен секретный ключ из панели Remnawave."
    printf_description "Найти его можно: Панель -> Nodes -> Add Node -> Secret Key"
    echo ""

    local secret_key
    secret_key=$(ask_non_empty "Секретный ключ ноды") || return

    echo ""
    local node_port
    node_port=$(safe_read "Порт ноды" "2420") || return

    if ! validate_port "$node_port"; then
        err "Некорректный порт, братан."
        return
    fi

    echo ""
    info "Открываю порт ${node_port}/tcp в UFW..."
    if command -v ufw &>/dev/null; then
        run_cmd ufw allow "${node_port}"/tcp comment 'Remnanode'
        ok "Порт ${node_port}/tcp открыт."
    else
        warn "UFW не найден, открой порт вручную."
    fi

    echo ""
    info "Погнали ставить ноду... Это может занять пару минут."
    print_separator
    echo ""

    curl -Ls https://github.com/DigneZzZ/remnawave-scripts/raw/main/remnanode.sh -o /tmp/_lumaxadm_rn.sh && bash /tmp/_lumaxadm_rn.sh @ install \
        --force --secret-key="$secret_key" --port="$node_port"; rm -f /tmp/_lumaxadm_rn.sh

    local exit_code=$?
    echo ""
    if [[ $exit_code -eq 0 ]]; then
        ok "Нода установлена! Красавчик."
        if command -v remnanode &>/dev/null; then
            info "Управлять нодой: ${C_CYAN}remnanode${C_RESET}"
        fi
    else
        err "Установка завершилась с ошибкой. Проверь логи выше."
    fi
}

_remna_run_node_script() {
    clear
    menu_header "📡 Скрипт управления нодой"
    info "Запускаю скрипт от Dignezzz..."
    echo ""
    remnanode
}

_remna_setup_node_logs() {
    clear
    menu_header "📝 Настройка логов Remnanode"

    info "После настройки логи ноды будут писаться в отдельные файлы:"
    echo ""
    printf_description "${C_WHITE}error:${C_RESET}  /var/log/remnanode/error.log"
    printf_description "${C_WHITE}access:${C_RESET} /var/log/remnanode/access.log"
    echo ""
    printf_description "${C_GRAY}Логи будут автоматически ротироваться (макс. 50MB, 5 архивов).${C_RESET}"
    echo ""

    if ! ask_yes_no "Настроить логи?"; then
        info "Отмена. Логи остаются как есть."
        return
    fi

    echo ""
    local compose_file="/opt/remnanode/docker-compose.yml"

    if [[ ! -f "$compose_file" ]]; then
        err "Файл ${compose_file} не найден. Нода установлена?"
        return
    fi

    # Шаг 1: Создаём директорию
    info "Создаю директорию /var/log/remnanode..."
    run_cmd mkdir -p /var/log/remnanode
    ok "Директория создана."

    # Шаг 2: Добавляем volume в docker-compose.yml
    info "Настраиваю docker-compose.yml..."
    run_cmd cp "$compose_file" "${compose_file}.bak_lumaxadm_$(date +%s)"

    # Проверяем не раскомментирован ли уже volume логов
    if grep -qE "^[[:space:]]*-.*(/var/log/remnanode:/var/log/remnanode)" "$compose_file"; then
        ok "Volume для логов уже прописан в docker-compose.yml."
    else
        # Случай 1: есть закомментированный volumes и наш volume внутри
        if grep -qE "^[[:space:]]*#[[:space:]]*volumes:" "$compose_file" && \
           grep -qE "^[[:space:]]*#.*-.*(/var/log/remnanode)" "$compose_file"; then
            # Раскомментируем секцию volumes
            run_cmd sed -i 's|^[[:space:]]*#[[:space:]]*\(volumes:\)|\    \1|' "$compose_file"
            # Раскомментируем строку с логами
            run_cmd sed -i 's|^[[:space:]]*#[[:space:]]*\(-[[:space:]]*/var/log/remnanode:/var/log/remnanode\)|      \1|' "$compose_file"
            ok "Volume для логов раскомментирован в docker-compose.yml."

        # Случай 2: есть закомментированный volumes, но нашего volume нет
        elif grep -qE "^[[:space:]]*#[[:space:]]*volumes:" "$compose_file"; then
            # Раскомментируем секцию volumes
            run_cmd sed -i 's|^[[:space:]]*#[[:space:]]*\(volumes:\)|\    \1|' "$compose_file"
            # Добавляем наш volume после volumes:
            run_cmd sed -i '/^[[:space:]]*volumes:/a \      - /var/log/remnanode:/var/log/remnanode' "$compose_file"
            ok "Volume для логов добавлен в docker-compose.yml."

        # Случай 3: есть раскомментированный volumes
        elif grep -qE "^[[:space:]]*volumes:" "$compose_file"; then
            run_cmd sed -i '/^[[:space:]]*volumes:/a \      - /var/log/remnanode:/var/log/remnanode' "$compose_file"
            ok "Volume для логов добавлен в docker-compose.yml."

        # Случай 4: volumes вообще нет
        else
            if grep -q "restart:" "$compose_file"; then
                run_cmd sed -i '/restart:/a \    volumes:\n      - /var/log/remnanode:/var/log/remnanode' "$compose_file"
            else
                echo '    volumes:' | run_cmd tee -a "$compose_file" >/dev/null
                echo '      - /var/log/remnanode:/var/log/remnanode' | run_cmd tee -a "$compose_file" >/dev/null
            fi
            ok "Volume для логов добавлен в docker-compose.yml."
        fi
    fi

    # Шаг 3: Устанавливаем logrotate
    info "Проверяю logrotate..."
    if ! command -v logrotate &>/dev/null; then
        info "Устанавливаю logrotate..."
        run_cmd apt-get update -qq >/dev/null 2>&1
        run_cmd apt-get install -y logrotate >/dev/null 2>&1
        ok "logrotate установлен."
    else
        ok "logrotate уже есть."
    fi

    # Шаг 4: Создаём конфиг ротации логов
    info "Настраиваю ротацию логов..."
    cat > /tmp/_lumaxadm_logrotate_remnanode << 'LOGROTATE_EOF'
/var/log/remnanode/*.log {
    size 50M
    rotate 5
    compress
    missingok
    notifempty
    copytruncate
}
LOGROTATE_EOF
    run_cmd cp /tmp/_lumaxadm_logrotate_remnanode /etc/logrotate.d/remnanode
    run_cmd chmod 644 /etc/logrotate.d/remnanode
    rm -f /tmp/_lumaxadm_logrotate_remnanode
    ok "Конфиг ротации создан."

    # Шаг 5: Тестируем logrotate
    info "Проверяю конфиг logrotate..."
    if logrotate -vf /etc/logrotate.d/remnanode >/dev/null 2>&1; then
        ok "Logrotate работает корректно."
    else
        warn "Logrotate выдал предупреждение, но это нормально если логов ещё нет."
    fi

    # Шаг 6: Перезапускаем ноду через docker compose (не через remnanode — он интерактивный)
    echo ""
    info "Перезапускаю ноду чтобы подхватила новые настройки..."
    (cd /opt/remnanode && docker compose down && docker compose up -d) >/dev/null 2>&1
    ok "Нода перезапущена."

    echo ""
    ok "Готово! Логи настроены. Теперь access.log и error.log пишутся в /var/log/remnanode/"
    info "Посмотреть: ${C_CYAN}tail -f /var/log/remnanode/access.log${C_RESET}"
}

_remna_install_selfsteal() {
    clear
    menu_header "🌐 Установка Caddy Selfsteal"
    info "Запускаю установщик от Dignezzz..."
    echo ""
    curl -Ls https://github.com/DigneZzZ/remnawave-scripts/raw/main/selfsteal.sh -o /tmp/_lumaxadm_ss.sh && bash /tmp/_lumaxadm_ss.sh @ install; rm -f /tmp/_lumaxadm_ss.sh
    echo ""
    if command -v selfsteal &>/dev/null; then
        ok "Caddy Selfsteal установлен!"
        info "Управлять можно командой: ${C_CYAN}selfsteal${C_RESET}"
    else
        err "Что-то пошло не так при установке."
    fi
}

_remna_run_selfsteal() {
    clear
    menu_header "🌐 Caddy Selfsteal"
    info "Запускаю Selfsteal..."
    echo ""
    selfsteal
}

_remna_install_warp() {
    clear
    menu_header "🌀 Установка WARP"
    info "Запускаю установщик WARP от Dignezzz..."
    echo ""
    curl -sL https://github.com/DigneZzZ/remnawave-scripts/raw/main/wtm.sh -o /tmp/_lumaxadm_wtm.sh && sudo bash /tmp/_lumaxadm_wtm.sh install-warp; rm -f /tmp/_lumaxadm_wtm.sh
    echo ""
    if command -v wtm &>/dev/null; then
        ok "WARP установлен!"
        info "Управлять можно командой: ${C_CYAN}wtm${C_RESET}"
    else
        err "Что-то пошло не так при установке."
    fi
}

_remna_run_warp() {
    clear
    menu_header "🌀 WARP Manager"
    info "Запускаю WARP Manager..."
    echo ""
    wtm
}

_remna_install_netbird() {
    clear
    menu_header "🐦 Установка NetBird"

    info "Для подключения к сети NetBird нужен Setup Key."
    printf_description "Найти его можно: ${C_CYAN}app.netbird.io${C_RESET} → Setup Keys → Create"
    echo ""

    local setup_key
    setup_key=$(ask_non_empty "Setup Key") || return

    echo ""
    info "Устанавливаю NetBird..."
    if curl -fsSL https://pkgs.netbird.io/install.sh | sh; then
        echo ""
        info "Подключаю к сети..."
        netbird up --setup-key "$setup_key"
        echo ""
        if netbird status 2>/dev/null | grep -q "Connected"; then
            ok "NetBird установлен и подключён! Красава."
        else
            ok "NetBird установлен. Проверь статус: ${C_CYAN}netbird status${C_RESET}"
        fi
    else
        err "Не удалось установить NetBird."
    fi
}

_remna_netbird_menu() {
    enable_graceful_ctrlc
    while true; do
        clear
        menu_header "🐦 NetBird — Управление"

        # Статус
        local nb_status
        nb_status=$(netbird status 2>/dev/null | head -5)
        if echo "$nb_status" | grep -q "Connected"; then
            printf_description "Статус: ${C_GREEN}Подключён${C_RESET}"
        elif echo "$nb_status" | grep -q "Disconnected"; then
            printf_description "Статус: ${C_RED}Отключён${C_RESET}"
        else
            printf_description "Статус: ${C_YELLOW}Неизвестно${C_RESET}"
        fi

        local nb_ip
        nb_ip=$(netbird status 2>/dev/null | grep -oE 'NetBird IP: [0-9./]+' | cut -d' ' -f3)
        if [[ -n "$nb_ip" ]]; then
            printf_description "NetBird IP: ${C_CYAN}${nb_ip}${C_RESET}"
        fi

        local nb_version
        nb_version=$(netbird version 2>/dev/null | head -1)
        if [[ -n "$nb_version" ]]; then
            printf_description "Версия: ${C_GRAY}${nb_version}${C_RESET}"
        fi

        echo ""
        printf_menu_option "1" "📊 Полный статус"
        printf_menu_option "2" "🟢 Подключиться (up)"
        printf_menu_option "3" "🔴 Отключиться (down)"
        printf_menu_option "4" "🔄 Переподключить"
        echo ""
        printf_menu_option "b" "Назад"
        echo ""

        local choice
        choice=$(safe_read "Выбирай" "") || break

        case "$choice" in
            1)
                echo ""
                netbird status
                wait_for_enter
                ;;
            2)
                info "Подключаюсь к NetBird..."
                netbird up
                ok "Готово."
                wait_for_enter
                ;;
            3)
                info "Отключаюсь от NetBird..."
                netbird down
                ok "Отключён."
                wait_for_enter
                ;;
            4)
                info "Переподключаюсь..."
                netbird down 2>/dev/null
                sleep 1
                netbird up
                ok "Переподключение завершено."
                wait_for_enter
                ;;
            b|B) break ;;
            *) warn "Нет такого пункта." && sleep 1 ;;
        esac
    done
    disable_graceful_ctrlc
}

# ============================================================ #
# ==          АВТО-УСТАНОВКА НОДЫ ПОД КЛЮЧ                   == #
# ============================================================ #
# Один пункт меню — десять шагов автоматом + одна опция в конце.
# Все вопросы задаются в начале, дальше настройка идёт без перерывов.

_remna_auto_node_setup() {
    clear
    menu_header "🚀 УСТАНОВКА НОДЫ ПОД КЛЮЧ"

    cat <<'DESCRIPTION'

[i] Этот мастер настроит сервер под ноду Remnawave одним заходом.
    Я задам несколько вопросов СРАЗУ, потом настройка пойдёт без
    перерывов до самого конца.

📋 ЧТО БУДЕТ СДЕЛАНО (10 шагов + 1 опционально):

   1. UFW Firewall — установка (если ещё нет)
   2. Сброс правил UFW + базовая конфигурация
      (deny incoming / allow outgoing)
   3. Открытие портов: SSH, IP панели (полный доступ),
      443/tcp+udp, 8443/tcp+udp → Включение UFW
   4. Fail2Ban — установка (если нет) + базовый jail.local
      (bantime=1ч, maxretry=5, findtime=600сек)
   5. TrafficGuard (антисканер) — установка + активация
      со стандартным community-листом
   6. Kernel Hardening — sysctl-усиления ядра от атак
   7. Сеть «Форсаж» — BBR + CAKE для max пропускной
   8. Отключение IPv6 (на уровне ядра)
   9. Отключение ICMP ping
  10. Установка Remnanode + настройка ротации логов
  11. (Опционально) Установка Caddy Selfsteal — спросим в конце

DESCRIPTION

    if ! ask_yes_no "Поехали?" "y"; then
        info "Отмена."
        return
    fi

    # ============================================================
    # PRE-COLLECTION
    # ============================================================
    print_separator
    info "🎙️  ОПРОС: ввожу все параметры заранее"
    print_separator

    # Robust detection: sshd_config.d > sshd_config > ss -tlnp (что реально слушает)
    local current_ssh_port
    current_ssh_port=$(grep -h "^Port " /etc/ssh/sshd_config.d/*.conf 2>/dev/null | tail -1 | awk '{print $2}')
    if [[ -z "$current_ssh_port" ]]; then
        current_ssh_port=$(grep "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    fi
    if [[ -z "$current_ssh_port" ]]; then
        # Последний fallback — что РЕАЛЬНО слушает sshd
        current_ssh_port=$(ss -tlnp 2>/dev/null | grep -E "sshd|ssh" | awk '{print $4}' | grep -oE '[0-9]+$' | head -1)
    fi
    current_ssh_port=${current_ssh_port:-22}

    info "Текущий SSH порт обнаружен: ${C_CYAN}${current_ssh_port}${C_RESET}"
    local ssh_port
    ssh_port=$(safe_read "На каком порту должен быть SSH (Enter = оставить как есть)" "$current_ssh_port") || return
    if ! validate_port "$ssh_port"; then
        err "Некорректный порт."; return
    fi

    local panel_ip
    panel_ip=$(ask_non_empty "IP адрес Панели управления (полный доступ к ноде)") || return
    if ! validate_ip "$panel_ip"; then
        err "Некорректный IP."; return
    fi

    info "Секретный ключ ноды: Панель → Nodes → Add Node → Secret Key"
    local secret_key
    secret_key=$(ask_non_empty "Секретный ключ ноды") || return

    local node_port
    node_port=$(safe_read "Порт ноды" "2420") || return
    if ! validate_port "$node_port"; then
        err "Некорректный порт ноды."; return
    fi

    # ============================================================
    # CONFIRMATION
    # ============================================================
    echo ""
    print_separator
    info "📝 СВОДКА:"
    if [[ "$ssh_port" != "$current_ssh_port" ]]; then
        printf_description "  SSH порт:        ${C_RED}${current_ssh_port} → ${ssh_port}${C_RESET} ${C_YELLOW}(будет миграция!)${C_RESET}"
    else
        printf_description "  SSH порт:        ${C_CYAN}${ssh_port}${C_RESET} ${C_GRAY}(без изменений)${C_RESET}"
    fi
    printf_description "  IP Панели:       ${C_CYAN}${panel_ip}${C_RESET}"
    printf_description "  Секретный ключ:  ${C_GRAY}${secret_key:0:24}…${C_RESET}"
    printf_description "  Порт ноды:       ${C_CYAN}${node_port}${C_RESET}"
    print_separator
    echo ""

    if [[ "$ssh_port" != "$current_ssh_port" ]]; then
        warn "⚠️  Будет миграция SSH с порта ${current_ssh_port} на ${ssh_port}."
        warn "    После миграции тебе нужно переподключиться по новому порту:"
        warn "    ${C_CYAN}ssh -p ${ssh_port} <user>@<server>${C_RESET}"
        warn "    Если миграция не удастся — авто-откат на ${current_ssh_port}."
        echo ""
    fi

    if ! ask_yes_no "Запускаю автоматическую настройку?" "y"; then
        info "Отмена."; return
    fi

    # Счётчики для итогов
    local _SETUP_DONE=()
    local _SETUP_FAIL=()
    _step_start() { printf "\n${C_BOLD}${C_BLUE}━━━ ▶️  ШАГ %s ━━━${C_RESET}\n" "$1"; }
    _step_ok()    { _SETUP_DONE+=("$1"); printf "${C_GREEN}━━━ ✅ ШАГ %s OK ━━━${C_RESET}\n" "$1"; sleep 1; }
    _step_fail()  { _SETUP_FAIL+=("$1"); printf "${C_RED}━━━ ⚠️  ШАГ %s FAIL ━━━${C_RESET}\n" "$1"; sleep 2; }

    # ============================================================
    # 1. UFW install
    # ============================================================
    _step_start "1/10: UFW Firewall — установка"
    if command -v ufw &>/dev/null; then
        ok "UFW уже установлен."
        _step_ok "1/10"
    else
        info "Устанавливаю UFW..."
        export DEBIAN_FRONTEND=noninteractive
        run_cmd apt-get update -qq >/dev/null 2>&1
        if run_cmd apt-get install -y -qq ufw >/dev/null 2>&1; then
            ok "UFW установлен."
            _step_ok "1/10"
        else
            err "Не удалось установить UFW. Прерываю — без него дальше нет смысла."
            _step_fail "1/10: apt install ufw"
            return
        fi
    fi

    # ============================================================
    # 2. Миграция SSH порта (если нужна) + UFW reset + правила + включение
    # ============================================================
    _step_start "2/10: Миграция SSH (если нужна) + UFW конфигурация"

    # effective_ssh_port — порт, на котором SSH РЕАЛЬНО будет слушать после этого шага
    # (если миграция удалась — это $ssh_port, иначе остаётся $current_ssh_port)
    local effective_ssh_port="$current_ssh_port"

    if [[ "$ssh_port" != "$current_ssh_port" ]]; then
        info "🔄 Мигрирую SSH с ${current_ssh_port} на ${ssh_port}..."
        local sshd_backup="/etc/ssh/sshd_config.bak_lumaxadm_$(date +%s)"
        run_cmd cp /etc/ssh/sshd_config "$sshd_backup"

        # 1. Меняем порт в основном конфиге
        run_cmd sed -i -e "s/^#*Port .*/Port $ssh_port/" /etc/ssh/sshd_config
        if ! grep -q "^Port " /etc/ssh/sshd_config; then
            echo "Port $ssh_port" | run_cmd tee -a /etc/ssh/sshd_config >/dev/null
        fi

        # 2. И в sshd_config.d (приоритет на современных системах)
        if [[ -d /etc/ssh/sshd_config.d ]]; then
            echo "Port $ssh_port" | run_cmd tee /etc/ssh/sshd_config.d/99-lumaxadm-port.conf >/dev/null
        fi

        # 3. Ubuntu 24+ — ssh.socket рулит портом
        local migration_ok=0
        if systemctl is-active --quiet ssh.socket 2>/dev/null; then
            info "Обнаружен ssh.socket (Ubuntu 24+), правлю systemd unit..."
            run_cmd mkdir -p /etc/systemd/system/ssh.socket.d
            cat <<SOCKET_EOF | run_cmd tee /etc/systemd/system/ssh.socket.d/override.conf >/dev/null
[Socket]
ListenStream=
ListenStream=0.0.0.0:${ssh_port}
ListenStream=[::]:${ssh_port}
SOCKET_EOF
            run_cmd systemctl daemon-reload
            if run_cmd systemctl restart ssh.socket && run_cmd systemctl restart ssh.service; then
                migration_ok=1
            fi
        else
            run_cmd systemctl daemon-reload 2>/dev/null || true
            if run_cmd systemctl restart sshd 2>/dev/null || run_cmd systemctl restart ssh 2>/dev/null; then
                migration_ok=1
            fi
        fi

        if [[ $migration_ok -eq 1 ]]; then
            sleep 5
            # Проверяем по факту: реально слушает новый порт?
            if ss -tlnp 2>/dev/null | grep -q ":${ssh_port}"; then
                ok "✅ SSH теперь слушает порт ${ssh_port}."
                effective_ssh_port="$ssh_port"
            else
                migration_ok=0
                warn "SSH перезапустился, но не слушает ${ssh_port}. Откатываю..."
            fi
        fi

        if [[ $migration_ok -eq 0 ]]; then
            warn "❌ Миграция SSH не удалась. Откатываю на ${current_ssh_port}..."
            run_cmd mv "$sshd_backup" /etc/ssh/sshd_config
            run_cmd rm -f /etc/ssh/sshd_config.d/99-lumaxadm-port.conf 2>/dev/null
            run_cmd rm -rf /etc/systemd/system/ssh.socket.d 2>/dev/null
            run_cmd systemctl daemon-reload 2>/dev/null || true
            run_cmd systemctl restart ssh.socket 2>/dev/null || true
            run_cmd systemctl restart sshd 2>/dev/null || run_cmd systemctl restart ssh 2>/dev/null || true
            warn "Использую старый порт ${current_ssh_port} для UFW (SSH не тронут)."
            effective_ssh_port="$current_ssh_port"
            _SETUP_FAIL+=("2/10: SSH миграция (откат, продолжаю на старом порту)")
        fi

        # Сохраняем порт в conf
        set_config_var "SSH_PORT" "$effective_ssh_port" 2>/dev/null || true
    else
        ok "SSH остаётся на порту ${current_ssh_port}."
    fi

    info "Сбрасываю старые правила UFW..."
    run_cmd ufw --force reset >/dev/null
    info "Default политики: deny incoming, allow outgoing..."
    run_cmd ufw default deny incoming >/dev/null
    run_cmd ufw default allow outgoing >/dev/null
    if [[ -f "/etc/default/ufw" ]] && grep -q "^IPV6=yes" "/etc/default/ufw"; then
        run_cmd sed -i 's/^IPV6=yes/IPV6=no/' "/etc/default/ufw"
    fi
    info "Открываю SSH=${effective_ssh_port}, Panel=${panel_ip}, 443/tcp+udp, 8443/tcp+udp..."
    run_cmd ufw allow "${effective_ssh_port}"/tcp comment 'SSH' >/dev/null
    run_cmd ufw allow from "$panel_ip" comment 'Panel Full Access' >/dev/null
    run_cmd ufw allow 443/tcp comment 'VPN/HTTPS' >/dev/null
    run_cmd ufw allow 443/udp comment 'VPN/HTTP3' >/dev/null
    run_cmd ufw allow 8443/tcp comment 'VPN ALT' >/dev/null
    run_cmd ufw allow 8443/udp comment 'VPN ALT UDP' >/dev/null
    info "Включаю UFW..."
    if echo "y" | run_cmd ufw enable >/dev/null 2>&1; then
        ok "UFW активирован, SSH доступен на порту ${effective_ssh_port}."
        _step_ok "2/10"
    else
        _step_fail "2/10: ufw enable"
    fi

    # ============================================================
    # 4. Fail2Ban
    # ============================================================
    _step_start "3/10: Fail2Ban — установка + базовый jail.local"
    if ! command -v fail2ban-client &>/dev/null; then
        info "Устанавливаю Fail2Ban..."
        export DEBIAN_FRONTEND=noninteractive
        run_cmd apt-get install -y -qq fail2ban >/dev/null 2>&1 || true
    else
        ok "Fail2Ban уже установлен."
    fi
    if command -v fail2ban-client &>/dev/null; then
        local f2b_logpath="/var/log/auth.log"
        local f2b_backend="auto"
        if [[ ! -f "$f2b_logpath" ]] && command -v journalctl &>/dev/null; then
            f2b_logpath="SYSLOG"
            f2b_backend="systemd"
        fi
        info "Создаю /etc/fail2ban/jail.local (bantime=1ч, maxretry=5, findtime=600с, port=${effective_ssh_port})..."
        run_cmd tee /etc/fail2ban/jail.local > /dev/null <<JAIL
[DEFAULT]
bantime = 3600
findtime = 600s
maxretry = 5
backend = $f2b_backend
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = $effective_ssh_port
filter = sshd
logpath = $f2b_logpath
JAIL
        run_cmd systemctl enable fail2ban >/dev/null 2>&1 || true
        run_cmd systemctl restart fail2ban
        sleep 1
        if systemctl is-active --quiet fail2ban; then
            ok "Fail2Ban запущен и защищает порт ${effective_ssh_port}."
            _step_ok "3/10"
        else
            _step_fail "3/10: fail2ban service не стартовал"
        fi
    else
        _step_fail "3/10: fail2ban не установился"
    fi

    # ============================================================
    # 5. TrafficGuard
    # ============================================================
    _step_start "4/10: TrafficGuard (антисканер)"
    if [[ -f "${SCRIPT_DIR}/modules/security/trafficguard.sh" ]]; then
        source "${SCRIPT_DIR}/modules/security/trafficguard.sh"
        if ! _tg_is_installed; then
            info "Устанавливаю TrafficGuard (скачивание + установка занимает до минуты)..."
            # Не редиректим в /dev/null — показываем прогресс юзеру.
            # </dev/null закрывает stdin (если установщик решит что-то спросить — не зависнет).
            # timeout 180 — на случай реального зависания.
            if timeout 180 bash -c "curl -fsSL '$_TG_INSTALL_URL' | bash" </dev/null; then
                ok "TrafficGuard установлен."
            else
                warn "Установка TrafficGuard вышла за timeout или провалилась."
            fi
        else
            ok "TrafficGuard уже установлен."
        fi
        if _tg_is_installed; then
            if _tg_is_running; then
                ok "TrafficGuard уже работает."
                _step_ok "4/10"
            else
                info "Активирую TrafficGuard со стандартным списком (скачивает ~100K подсетей)..."
                # Показываем вывод бинаря, закрываем stdin, ставим timeout 5 минут.
                if timeout 300 traffic-guard full -u "$_TG_LIST_URL" </dev/null; then
                    ok "TrafficGuard активирован."
                    _step_ok "4/10"
                else
                    local rc=$?
                    if [[ $rc -eq 124 ]]; then
                        _step_fail "4/10: traffic-guard завис (timeout 5 мин)"
                    else
                        _step_fail "4/10: traffic-guard full exit=$rc"
                    fi
                fi
            fi
        else
            _step_fail "4/10: install"
        fi
    else
        warn "Модуль trafficguard.sh не найден — пропуск."
        _step_fail "4/10: модуль не найден"
    fi

    # ============================================================
    # 6. Kernel Hardening
    # ============================================================
    _step_start "5/10: Kernel Hardening"
    local SYSCTL_HARDEN="/etc/sysctl.d/99-lumaxadm-hardening.conf"
    info "Создаю $SYSCTL_HARDEN..."
    run_cmd tee "$SYSCTL_HARDEN" > /dev/null << 'SYSCTL_HARDEN_EOF'
# Generated by LumaxADM Auto-Setup (Kernel Hardening)
# --- SYN Flood Protection ---
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_max_syn_backlog = 4096
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 4096

# --- IP Spoofing & Network Attack Protection ---
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# --- TCP Tuning ---
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15

# --- Kernel Security ---
kernel.randomize_va_space = 2
kernel.dmesg_restrict = 1
kernel.yama.ptrace_scope = 1
fs.protected_symlinks = 1
fs.protected_hardlinks = 1
SYSCTL_HARDEN_EOF
    if run_cmd sysctl -p "$SYSCTL_HARDEN" >/dev/null 2>&1; then
        ok "Kernel Hardening применён."
        _step_ok "5/10"
    else
        _step_fail "5/10: sysctl -p hardening"
    fi

    # ============================================================
    # 7. Forsage (BBR + CAKE)
    # ============================================================
    _step_start "6/10: Сеть «Форсаж» (BBR + CAKE)"
    local cake_avail="false"
    modprobe sch_cake &>/dev/null && cake_avail="true"
    local pref_cc="bbr"
    sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -q "bbr2" && pref_cc="bbr2"
    local pref_qdisc="fq"
    [[ "$cake_avail" == "true" ]] && pref_qdisc="cake"
    local SYSCTL_BOOST="/etc/sysctl.d/99-lumaxadm-boost.conf"
    info "Создаю $SYSCTL_BOOST..."
    run_cmd tee "$SYSCTL_BOOST" > /dev/null <<EOF_BOOST
# === КОНФИГ «ФОРСАЖ» ОТ LUMAXADM ===
net.core.default_qdisc = ${pref_qdisc}
net.ipv4.tcp_congestion_control = ${pref_cc}
net.ipv4.tcp_fastopen = 3
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
EOF_BOOST
    if run_cmd sysctl -p "$SYSCTL_BOOST" >/dev/null 2>&1; then
        ok "«Форсаж» включён (CC=${pref_cc}, QDisc=${pref_qdisc})."
        _step_ok "6/10"
    else
        _step_fail "6/10: sysctl -p forsage"
    fi

    # ============================================================
    # 8. Disable IPv6
    # ============================================================
    _step_start "7/10: Отключение IPv6"
    run_cmd tee /etc/sysctl.d/98-disable-ipv6.conf > /dev/null <<EOF_NO6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF_NO6
    if run_cmd sysctl -p /etc/sysctl.d/98-disable-ipv6.conf >/dev/null 2>&1; then
        ok "IPv6 отключён."
        _step_ok "7/10"
    else
        _step_fail "7/10: sysctl -p ipv6"
    fi

    # ============================================================
    # 9. Disable ICMP ping
    # ============================================================
    _step_start "8/10: Отключение ICMP ping"
    local before_rules="/etc/ufw/before.rules"
    if [[ -f "$before_rules" ]]; then
        run_cmd cp "$before_rules" "${before_rules}.bak_lumaxadm_$(date +%s)"
        run_cmd sed -i 's|-A ufw-before-input -p icmp --icmp-type destination-unreachable -j ACCEPT|-A ufw-before-input -p icmp --icmp-type destination-unreachable -j DROP|g' "$before_rules"
        run_cmd sed -i 's|-A ufw-before-input -p icmp --icmp-type time-exceeded -j ACCEPT|-A ufw-before-input -p icmp --icmp-type time-exceeded -j DROP|g' "$before_rules"
        run_cmd sed -i 's|-A ufw-before-input -p icmp --icmp-type parameter-problem -j ACCEPT|-A ufw-before-input -p icmp --icmp-type parameter-problem -j DROP|g' "$before_rules"
        run_cmd sed -i 's|-A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT|-A ufw-before-input -p icmp --icmp-type echo-request -j DROP|g' "$before_rules"
        run_cmd ufw reload >/dev/null 2>&1 || true
        ok "ICMP заблокирован."
        _step_ok "8/10"
    else
        warn "before.rules не найден — пропуск."
        _step_fail "8/10: before.rules не найден"
    fi

    # ============================================================
    # 10. Install Remnanode + ротация логов
    # ============================================================
    _step_start "9/10: Установка Remnanode + ротация логов"
    info "Открываю порт ${node_port}/tcp в UFW..."
    run_cmd ufw allow "${node_port}"/tcp comment 'Remnanode' >/dev/null
    run_cmd ufw reload >/dev/null 2>&1 || true

    info "Скачиваю установщик ноды (Dignezzz)..."
    curl -Ls https://github.com/DigneZzZ/remnawave-scripts/raw/main/remnanode.sh -o /tmp/_lumaxadm_rn.sh

    info "Запускаю установщик. Жму отбой автоматически как только контейнер поднимется."
    info "Можешь нажать Ctrl+C если надоест ждать (нода уже в detached режиме)."

    # Установщик от Dignezzz после 'docker compose up -d' стримит логи на foreground.
    # Запускаем в фоне, поллим docker ps — как только контейнер remnanode появится,
    # убиваем foreground (контейнер останется работать, он detached).
    # Hard timeout 180s = страховка если что-то совсем пошло не так.
    bash /tmp/_lumaxadm_rn.sh @ install --force --secret-key="$secret_key" --port="$node_port" </dev/null &
    local install_pid=$!

    local waited=0
    local node_running=0
    local POLL_INTERVAL=3
    local POLL_MAX=180  # 3 минуты hard cap
    while [[ $waited -lt $POLL_MAX ]]; do
        # Если установщик сам завершился (нормально или с ошибкой) — выходим из поллинга
        if ! kill -0 "$install_pid" 2>/dev/null; then
            break
        fi
        sleep "$POLL_INTERVAL"
        waited=$((waited + POLL_INTERVAL))
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^remnanode"; then
            ok "Контейнер remnanode поднят за ${waited}с, продолжаю авто-настройку..."
            kill -TERM "$install_pid" 2>/dev/null
            sleep 1
            kill -KILL "$install_pid" 2>/dev/null
            wait "$install_pid" 2>/dev/null
            node_running=1
            break
        fi
    done

    # Если поллинг закончился без поднятия контейнера — добиваем установщик и проверяем последний раз
    if [[ $node_running -eq 0 ]]; then
        kill -TERM "$install_pid" 2>/dev/null
        wait "$install_pid" 2>/dev/null
        sleep 2
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^remnanode"; then
            ok "Контейнер remnanode подъехал к финишу, идём дальше."
            node_running=1
        else
            warn "Контейнер remnanode не обнаружен после ${waited}с ожидания."
        fi
    fi
    rm -f /tmp/_lumaxadm_rn.sh

    # Ротация логов — выполняется НЕЗАВИСИМО от install_rc, если есть compose-файл.
    # Так setup логов не пропускается даже если установщик «завис на логах».
    local compose_file="/opt/remnanode/docker-compose.yml"
    if [[ -f "$compose_file" ]]; then
        info "Настраиваю ротацию логов ноды..."
        run_cmd mkdir -p /var/log/remnanode
        run_cmd cp "$compose_file" "${compose_file}.bak_lumaxadm_$(date +%s)"

        if grep -qE "^[[:space:]]*-.*(/var/log/remnanode:/var/log/remnanode)" "$compose_file"; then
            ok "Volume логов уже прописан."
        elif grep -qE "^[[:space:]]*#[[:space:]]*volumes:" "$compose_file" && \
             grep -qE "^[[:space:]]*#.*-.*(/var/log/remnanode)" "$compose_file"; then
            run_cmd sed -i 's|^[[:space:]]*#[[:space:]]*\(volumes:\)|\    \1|' "$compose_file"
            run_cmd sed -i 's|^[[:space:]]*#[[:space:]]*\(-[[:space:]]*/var/log/remnanode:/var/log/remnanode\)|      \1|' "$compose_file"
            ok "Volume логов раскомментирован."
        elif grep -qE "^[[:space:]]*volumes:" "$compose_file"; then
            run_cmd sed -i '/^[[:space:]]*volumes:/a \      - /var/log/remnanode:/var/log/remnanode' "$compose_file"
            ok "Volume логов добавлен."
        else
            warn "Не нашёл секцию volumes в compose — пропуск автоматического добавления."
        fi

        if ! command -v logrotate &>/dev/null; then
            run_cmd apt-get install -y -qq logrotate >/dev/null 2>&1 || true
        fi

        cat > /tmp/_lumaxadm_lr_remnanode <<'LR_EOF'
/var/log/remnanode/*.log {
    size 50M
    rotate 5
    compress
    missingok
    notifempty
    copytruncate
}
LR_EOF
        run_cmd cp /tmp/_lumaxadm_lr_remnanode /etc/logrotate.d/remnanode
        run_cmd chmod 644 /etc/logrotate.d/remnanode
        rm -f /tmp/_lumaxadm_lr_remnanode
        ok "Logrotate config создан."

        info "Перезапускаю ноду чтобы compose подхватил новый volume..."
        (cd /opt/remnanode && docker compose down && docker compose up -d) >/dev/null 2>&1
        ok "Ротация логов настроена."

        if [[ $node_running -eq 1 ]]; then
            _step_ok "9/10"
        else
            # Контейнер не был, но compose-файл есть → возможно пытаемся прямо сейчас поднять
            sleep 3
            if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^remnanode"; then
                ok "Контейнер поднят после правки compose."
                _step_ok "9/10"
            else
                _step_fail "9/10: контейнер remnanode не стартовал"
            fi
        fi
    else
        warn "compose-файл /opt/remnanode/docker-compose.yml не найден."
        _step_fail "9/10: compose-файл отсутствует (установка ноды провалилась)"
    fi

    # ============================================================
    # 11. Caddy Selfsteal — спрашиваем В КОНЦЕ
    # ============================================================
    _step_start "10/10: Caddy Selfsteal (опционально)"
    echo ""
    if ask_yes_no "Установить Caddy Selfsteal сейчас?" "y"; then
        info "Запускаю установщик Caddy Selfsteal (Dignezzz)..."
        if curl -Ls https://github.com/DigneZzZ/remnawave-scripts/raw/main/selfsteal.sh -o /tmp/_lumaxadm_ss.sh && \
           bash /tmp/_lumaxadm_ss.sh @ install; then
            rm -f /tmp/_lumaxadm_ss.sh
            ok "Caddy Selfsteal установлен."
            _step_ok "10/10"
        else
            rm -f /tmp/_lumaxadm_ss.sh
            _step_fail "10/10: установщик selfsteal"
        fi
    else
        info "Caddy Selfsteal пропущен."
        _SETUP_DONE+=("10/10 (пропущен по запросу)")
    fi

    # ============================================================
    # ИТОГ
    # ============================================================
    clear
    menu_header "🎉 ИТОГ АВТО-УСТАНОВКИ"
    echo ""
    info "✅ Успешные шаги (${#_SETUP_DONE[@]}):"
    for s in "${_SETUP_DONE[@]}"; do
        printf_description "  ${C_GREEN}✓${C_RESET} ${s}"
    done

    if [[ ${#_SETUP_FAIL[@]} -gt 0 ]]; then
        echo ""
        warn "⚠️  Шаги с ошибками (${#_SETUP_FAIL[@]}):"
        for s in "${_SETUP_FAIL[@]}"; do
            printf_description "  ${C_RED}✗${C_RESET} ${s}"
        done
    fi

    echo ""
    print_separator
    info "📊 Полезные команды для проверки:"
    printf_description "  Статус UFW:           ${C_CYAN}ufw status verbose${C_RESET}"
    printf_description "  Статус Fail2Ban:      ${C_CYAN}fail2ban-client status sshd${C_RESET}"
    printf_description "  Статус TrafficGuard:  ${C_CYAN}traffic-guard status${C_RESET}"
    printf_description "  Логи ноды:            ${C_CYAN}tail -f /var/log/remnanode/access.log${C_RESET}"
    printf_description "  Управление нодой:     ${C_CYAN}remnanode${C_RESET}"
    if command -v selfsteal &>/dev/null; then
        printf_description "  Caddy Selfsteal:      ${C_CYAN}selfsteal${C_RESET}"
    fi
    print_separator

    echo ""
    if [[ ${#_SETUP_FAIL[@]} -eq 0 ]]; then
        ok "🚀 Установка завершена успешно. Сервер готов к работе!"
    else
        warn "Установка завершена с предупреждениями. Проверь шаги с ошибками."
    fi
    echo ""
    wait_for_enter
}


# --- Меню ---

show_remnawave_centre_menu() {
    enable_graceful_ctrlc
    while true; do
        clear
        menu_header "💿 Remnawave — Панель и Нода"
        printf_description "Установка и управление VPN-инфраструктурой Remnawave."

        local has_panel=0
        local has_node=0
        local has_panel_script=0
        local has_node_script=0

        _remna_panel_installed && has_panel=1
        _remna_node_installed && has_node=1
        _remna_panel_script_installed && has_panel_script=1
        _remna_node_script_installed && has_node_script=1

        # Статус сверху
        echo ""
        printf "  ${C_GRAY}Панель:${C_RESET} "
        if [[ $has_panel -eq 1 ]]; then
            printf "${C_GREEN}установлена${C_RESET}"
            [[ $has_panel_script -eq 1 ]] && printf " ${C_GRAY}| скрипт: ${C_GREEN}есть${C_RESET}" || printf " ${C_GRAY}| скрипт: ${C_RED}нет${C_RESET}"
        else
            printf "${C_GRAY}не обнаружена${C_RESET}"
        fi
        echo ""
        printf "  ${C_GRAY}Нода:${C_RESET}   "
        if [[ $has_node -eq 1 ]]; then
            printf "${C_GREEN}установлена${C_RESET}"
            [[ $has_node_script -eq 1 ]] && printf " ${C_GRAY}| скрипт: ${C_GREEN}есть${C_RESET}" || printf " ${C_GRAY}| скрипт: ${C_RED}нет${C_RESET}"
        else
            printf "${C_RED}не установлена${C_RESET}"
        fi
        echo ""
        echo ""

        # --- АВТО-УСТАНОВКА (под ключ) ---
        if [[ $has_node -eq 0 ]]; then
            printf_menu_option "0" "🚀 Установка Ноды под ключ ${C_BOLD}${C_GREEN}(всё автоматом)${C_RESET}"
            echo ""
        fi

        # --- Управление ---
        if [[ $has_panel -eq 1 ]]; then
            if [[ $has_panel_script -eq 1 ]]; then
                printf_menu_option "1" "🖥️  Запустить скрипт управления панелью ${C_GREEN}(Dignezzz)${C_RESET}"
            else
                printf_menu_option "1" "🖥️  Установить скрипт управления панелью ${C_YELLOW}(Dignezzz)${C_RESET}"
            fi
        fi

        if [[ $has_node -eq 1 && $has_node_script -eq 1 ]]; then
            printf_menu_option "2" "📡 Запустить скрипт управления нодой ${C_GREEN}(Dignezzz)${C_RESET}"
        elif [[ $has_node -eq 1 ]]; then
            printf_menu_option "2" "📡 Установить скрипт управления нодой ${C_YELLOW}(Dignezzz)${C_RESET}"
        else
            printf_menu_option "2" "📡 Установить Remnanode ${C_CYAN}(нода ещё не стоит)${C_RESET}"
        fi

        echo ""

        # --- Доп. инструменты (только если нода есть) ---
        if [[ $has_node -eq 1 ]]; then
            printf_menu_option "3" "📝 Сменить путь логов ${C_GRAY}(Опционально)${C_RESET}"

            if _remna_selfsteal_installed; then
                printf_menu_option "4" "🌐 Запустить Caddy Selfsteal ${C_GREEN}(Dignezzz)${C_RESET}"
            else
                printf_menu_option "4" "🌐 Установить Caddy Selfsteal ${C_YELLOW}(Dignezzz)${C_RESET}"
            fi
        fi

        echo ""

        # --- WARP & NetBird ---
        if _remna_warp_installed; then
            printf_menu_option "5" "🌀 Запустить WARP Manager ${C_GREEN}(wtm)${C_RESET}"
        else
            printf_menu_option "5" "🌀 Установить WARP ${C_YELLOW}(Dignezzz)${C_RESET}"
        fi

        if command -v netbird &>/dev/null; then
            printf_menu_option "6" "🐦 Управление NetBird ${C_GREEN}(установлен)${C_RESET}"
        else
            printf_menu_option "6" "🐦 Установить NetBird ${C_YELLOW}(mesh VPN)${C_RESET}"
        fi

        echo ""
        printf_menu_option "b" "Назад"
        echo ""

        local choice
        choice=$(safe_read "Чё делаем?" "") || break

        case "$choice" in
            0)
                if [[ $has_node -eq 1 ]]; then
                    warn "Нода уже установлена — авто-установка в этом сервере не нужна."
                    sleep 2
                    continue
                fi
                _remna_auto_node_setup
                ;;
            1)
                if [[ $has_panel -eq 0 ]]; then
                    warn "Панель не установлена на этом сервере. Тут нечем управлять, братан."
                    sleep 2
                    continue
                fi
                if [[ $has_panel_script -eq 1 ]]; then
                    _remna_run_panel_script
                else
                    _remna_install_panel_script
                fi
                wait_for_enter
                ;;
            2)
                if [[ $has_node -eq 1 && $has_node_script -eq 1 ]]; then
                    _remna_run_node_script
                elif [[ $has_node -eq 1 ]]; then
                    clear
                    menu_header "📡 Установка скрипта управления нодой"
                    info "Ставлю скрипт от Dignezzz..."
                    echo ""
                    curl -Ls https://github.com/DigneZzZ/remnawave-scripts/raw/main/remnanode.sh -o /tmp/_lumaxadm_rn.sh && bash /tmp/_lumaxadm_rn.sh @ install-script --name remnanode; rm -f /tmp/_lumaxadm_rn.sh
                    if command -v remnanode &>/dev/null; then
                        ok "Скрипт управления нодой установлен!"
                        info "Запустить можно командой: ${C_CYAN}remnanode${C_RESET}"
                    else
                        err "Что-то пошло не так."
                    fi
                else
                    _remna_install_node
                fi
                wait_for_enter
                ;;
            3)
                if [[ $has_node -eq 1 ]]; then
                    _remna_setup_node_logs
                else
                    warn "Нода не установлена — логи некуда менять."
                fi
                wait_for_enter
                ;;
            4)
                if [[ $has_node -eq 0 ]]; then
                    warn "Нода не установлена — Selfsteal ставить некуда."
                elif _remna_selfsteal_installed; then
                    _remna_run_selfsteal
                else
                    _remna_install_selfsteal
                fi
                wait_for_enter
                ;;
            5)
                if _remna_warp_installed; then
                    _remna_run_warp
                else
                    _remna_install_warp
                fi
                wait_for_enter
                ;;
            6)
                if command -v netbird &>/dev/null; then
                    _remna_netbird_menu
                else
                    _remna_install_netbird
                    wait_for_enter
                fi
                ;;
            b|B) break ;;
            *) warn "Нет такого пункта." && sleep 1 ;;
        esac
    done
    disable_graceful_ctrlc
}
