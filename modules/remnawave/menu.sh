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
    printf_description "Найти его можно: Панель → Nodes → Add Node → Secret Key"
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

# --- Меню ---

show_remnawave_centre_menu() {
    enable_graceful_ctrlc
    while true; do
        clear
        menu_header "💿 Remnawave — Панель и Нода"
        printf_description "Установка и управление VPN-инфраструктурой Remnawave."
        echo ""

        local has_panel=0
        local has_node=0
        local has_panel_script=0
        local has_node_script=0

        _remna_panel_installed && has_panel=1
        _remna_node_installed && has_node=1
        _remna_panel_script_installed && has_panel_script=1
        _remna_node_script_installed && has_node_script=1

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

        echo ""

        # Статус
        print_separator "─" 60
        printf "  ${C_GRAY}Панель:${C_RESET} "
        if [[ $has_panel -eq 1 ]]; then
            printf "${C_GREEN}установлена${C_RESET}"
            [[ $has_panel_script -eq 1 ]] && printf " ${C_GRAY}| скрипт: ${C_GREEN}есть${C_RESET}" || printf " ${C_GRAY}| скрипт: ${C_RED}нет${C_RESET}"
        else
            printf "${C_GRAY}не обнаружена на этом сервере${C_RESET}"
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
        print_separator "─" 60

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
                    # Нода есть, скрипта нет — ставим скрипт
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
                    # Ноды нет — полная установка
                    _remna_install_node
                fi
                wait_for_enter
                ;;
            b|B) break ;;
            *) warn "Нет такого пункта." && sleep 1 ;;
        esac
    done
    disable_graceful_ctrlc
}
