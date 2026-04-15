#!/bin/bash
# ============================================================ #
# ==             REMNAWAVE: УПРАВЛЕНИЕ ПАНЕЛЬЮ И НОДОЙ       == #
# ============================================================ #
#  ( РОДИТЕЛЬ | КЛАВИША | НАЗВАНИЕ | ФУНКЦИЯ | ПОРЯДОК | ГРУППА | ОПИСАНИЕ )
# @menu.manifest
# @item( main | 7 | 💿 Remnawave ${C_YELLOW}(Панель и Нода)${C_RESET} | show_remnawave_centre_menu | 40 | 3 | Установка и управление панелью Remnawave и нодами. )
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

# --- Действия ---

_remna_install_panel_script() {
    clear
    menu_header "💿 Установка скрипта управления панелью"
    info "Ставлю скрипт от Dignezzz... Сейчас всё будет."
    echo ""
    bash <(curl -Ls https://github.com/DigneZzZ/remnawave-scripts/raw/main/remnawave.sh) @ install-script --name remnawave
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

    bash <(curl -Ls https://github.com/DigneZzZ/remnawave-scripts/raw/main/remnanode.sh) @ install \
        --force --secret-key="$secret_key" --port="$node_port"

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

    if grep -q "/var/log/remnanode:/var/log/remnanode" "$compose_file"; then
        ok "Volume для логов уже прописан в docker-compose.yml."
    else
        # Проверяем есть ли секция volumes
        if grep -q "^[[:space:]]*volumes:" "$compose_file"; then
            # volumes есть — добавляем строку после неё
            run_cmd sed -i '/^[[:space:]]*volumes:/a \      - "/var/log/remnanode:/var/log/remnanode"' "$compose_file"
        else
            # volumes нет — добавляем перед env_file или в конец сервиса
            if grep -q "env_file:" "$compose_file"; then
                run_cmd sed -i '/env_file:/i \    volumes:\n      - "/var/log/remnanode:/var/log/remnanode"' "$compose_file"
            else
                # Крайний случай — добавляем перед последней строкой
                echo '    volumes:' | run_cmd tee -a "$compose_file" >/dev/null
                echo '      - "/var/log/remnanode:/var/log/remnanode"' | run_cmd tee -a "$compose_file" >/dev/null
            fi
        fi
        ok "Volume добавлен в docker-compose.yml."
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

    # Шаг 6: Перезапускаем ноду
    echo ""
    info "Перезапускаю ноду чтобы подхватила новые настройки..."
    if command -v remnanode &>/dev/null; then
        remnanode restart >/dev/null 2>&1
        ok "Нода перезапущена."
    else
        # Fallback через docker compose
        (cd /opt/remnanode && docker compose down && docker compose up -d) >/dev/null 2>&1
        ok "Нода перезапущена через docker compose."
    fi

    echo ""
    ok "Готово! Логи настроены. Теперь access.log и error.log пишутся в /var/log/remnanode/"
    info "Посмотреть: ${C_CYAN}tail -f /var/log/remnanode/access.log${C_RESET}"
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

        # Пункт 1: Панель (только если панель установлена в Docker)
        if [[ $has_panel -eq 1 ]]; then
            if [[ $has_panel_script -eq 1 ]]; then
                printf_menu_option "1" "🖥️  Запустить скрипт управления панелью ${C_GREEN}(Dignezzz)${C_RESET}"
            else
                printf_menu_option "1" "🖥️  Установить скрипт управления панелью ${C_YELLOW}(Dignezzz)${C_RESET}"
            fi
        fi

        # Пункт 2: Нода (всегда виден)
        if [[ $has_node -eq 1 && $has_node_script -eq 1 ]]; then
            printf_menu_option "2" "📡 Запустить скрипт управления нодой ${C_GREEN}(Dignezzz)${C_RESET}"
        elif [[ $has_node -eq 1 ]]; then
            printf_menu_option "2" "📡 Установить скрипт управления нодой ${C_YELLOW}(Dignezzz)${C_RESET}"
        else
            printf_menu_option "2" "📡 Установить Remnanode ${C_CYAN}(нода ещё не стоит)${C_RESET}"
        fi

        # Пункт 3: Логи (только если нода есть)
        if [[ $has_node -eq 1 ]]; then
            printf_menu_option "3" "📝 Сменить путь логов ${C_GRAY}(Опционально)${C_RESET}"
        fi

        echo ""
        printf_menu_option "b" "Назад"
        echo ""

        local choice
        choice=$(safe_read "Чё делаем?" "") || break

        case "$choice" in
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
                    bash <(curl -Ls https://github.com/DigneZzZ/remnawave-scripts/raw/main/remnanode.sh) @ install-script --name remnanode
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
            b|B) break ;;
            *) warn "Нет такого пункта." && sleep 1 ;;
        esac
    done
    disable_graceful_ctrlc
}
