#!/bin/bash
# ============================================================ #
# ==           МОДУЛЬ TRAFFICGUARD (АНТИСКАНЕР)              == #
# ============================================================ #
#
#  ( РОДИТЕЛЬ | КЛАВИША | НАЗВАНИЕ | ФУНКЦИЯ | ПОРЯДОК | ГРУППА | ОПИСАНИЕ )
# @menu.manifest
# @item( security | 3 | 🚫 TrafficGuard (Антисканер) | show_trafficguard_menu | 25 | 10 | Блокировка сканеров портов через iptables+ipset. )
#
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1

readonly _TG_LIST_URL="https://raw.githubusercontent.com/shadow-netlab/traffic-guard-lists/refs/heads/main/public/antiscanner.list"
readonly _TG_INSTALL_URL="https://raw.githubusercontent.com/dotX12/traffic-guard/master/install.sh"
readonly _TG_LOG_FILE="/var/log/iptables-scanners-aggregate.csv"

_tg_is_installed() {
    command -v traffic-guard &>/dev/null
}

_tg_is_running() {
    iptables -L SCANNERS-BLOCK -n &>/dev/null 2>&1
}

_tg_install() {
    info "Устанавливаю TrafficGuard..."
    if curl -fsSL "$_TG_INSTALL_URL" | run_cmd bash; then
        ok "TrafficGuard установлен. Теперь можешь врубить защиту через [1]."
    else
        err "Не удалось установить TrafficGuard."
        return 1
    fi
}

_tg_uninstall() {
    if ! _tg_is_installed; then
        warn "TrafficGuard и так не установлен, сносить нечего."
        return
    fi

    if ! ask_yes_no "Точно удалить TrafficGuard? Все правила и бинарь будут снесены"; then
        info "Отмена. TrafficGuard остаётся."
        return
    fi

    # Сначала деактивируем если активен
    if _tg_is_running; then
        info "Снимаю защиту перед удалением..."
        run_cmd traffic-guard uninstall --yes --remove-logs 2>/dev/null || true
    fi

    # Удаляем бинарь
    if [[ -f "/usr/local/bin/traffic-guard" ]]; then
        run_cmd rm -f /usr/local/bin/traffic-guard
    fi

    ok "TrafficGuard полностью удалён. Чистенько."
}

_tg_activate() {
    if ! _tg_is_installed; then
        warn "TrafficGuard не установлен. Сначала поставь через [i]."
        return
    fi

    if _tg_is_running; then
        warn "Защита уже работает, братан. Всё ок."
        return
    fi

    info "Запускаю TrafficGuard с базовой защитой..."
    if run_cmd traffic-guard full -u "$_TG_LIST_URL"; then
        ok "TrafficGuard активирован. Сканеры заблокированы."
    else
        err "Не удалось запустить TrafficGuard."
    fi
}

_tg_deactivate() {
    if ! _tg_is_installed; then
        warn "TrafficGuard не установлен. Нечего отключать."
        return
    fi

    if ! _tg_is_running; then
        warn "Защита и так не активна."
        return
    fi

    if ask_yes_no "Отключить защиту? Правила будут удалены, но сам TrafficGuard останется"; then
        if run_cmd traffic-guard uninstall --yes; then
            ok "Защита снята. TrafficGuard остался установленным — можешь врубить обратно через [1]."
        else
            err "Не удалось деактивировать TrafficGuard."
        fi
    fi
}

_tg_show_status() {
    print_separator
    info "Статус TrafficGuard"
    print_separator

    if ! _tg_is_installed; then
        printf_description "Установлен: ${C_RED}Нет${C_RESET} ${C_GRAY}(нажми [i] чтобы поставить)${C_RESET}"
        return 1
    fi
    printf_description "Установлен: ${C_GREEN}Да${C_RESET}"

    if _tg_is_running; then
        printf_description "Защита:     ${C_GREEN}Активна${C_RESET}"

        # Количество заблокированных подсетей
        local v4_count v6_count
        v4_count=$(ipset list SCANNERS-BLOCK-V4 2>/dev/null | grep -c "^[0-9]" || echo "0")
        v6_count=$(ipset list SCANNERS-BLOCK-V6 2>/dev/null | grep -c "^[0-9a-f]" || echo "0")
        printf_description "Подсетей:   ${C_CYAN}${v4_count}${C_RESET} IPv4, ${C_CYAN}${v6_count}${C_RESET} IPv6"

        # Счётчик пакетов
        local dropped
        dropped=$(iptables -L SCANNERS-BLOCK -v -n 2>/dev/null | grep "DROP" | awk '{sum+=$1} END {print sum+0}')
        printf_description "Заблокировано пакетов: ${C_YELLOW}${dropped}${C_RESET}"
    else
        printf_description "Защита:     ${C_RED}Не активна${C_RESET}"
    fi
    return 0
}

_tg_show_logs() {
    if [[ ! -f "$_TG_LOG_FILE" ]]; then
        warn "Логи не найдены. Видимо логирование не включено или ещё ничего не заблочилось."
        return
    fi

    info "Последние заблокированные IP (из ${_TG_LOG_FILE}):"
    echo ""
    head -20 "$_TG_LOG_FILE" | column -t -s'|' 2>/dev/null || head -20 "$_TG_LOG_FILE"
}

show_trafficguard_menu() {
    enable_graceful_ctrlc
    while true; do
        clear
        menu_header "🚫 TrafficGuard (Антисканер)"
        printf_description "Блокировка сканеров портов через iptables + ipset."

        local installed=1
        _tg_show_status || installed=0
        echo ""

        if [[ $installed -eq 0 ]]; then
            printf_menu_option "i" "📦 Установить TrafficGuard"
        else
            printf_menu_option "1" "Включить защиту"
            printf_menu_option "2" "Отключить защиту"
            printf_menu_option "3" "Показать логи блокировок"
            echo ""
            printf_menu_option "d" "🗑️  Удалить TrafficGuard ${C_RED}(полностью)${C_RESET}"
        fi
        echo ""
        printf_menu_option "b" "Назад"
        echo ""

        local choice
        choice=$(safe_read "Выбирай" "") || break

        case "$choice" in
            i|I)
                if [[ $installed -eq 0 ]]; then
                    _tg_install
                else
                    warn "Уже установлен, чего ещё ставить-то?"
                fi
                ;;
            1)
                if [[ $installed -eq 1 ]]; then
                    _tg_activate
                else
                    warn "Сначала поставь через [i], потом включай."
                fi
                ;;
            2)
                if [[ $installed -eq 1 ]]; then
                    _tg_deactivate
                else
                    warn "Нечего отключать — не установлено."
                fi
                ;;
            3)
                if [[ $installed -eq 1 ]]; then
                    _tg_show_logs
                else
                    warn "Нечего смотреть — не установлено."
                fi
                ;;
            d|D)
                if [[ $installed -eq 1 ]]; then
                    _tg_uninstall
                else
                    warn "Нечего удалять — и так не стоит."
                fi
                ;;
            b|B) break ;;
            *) warn "Нет такого пункта." && sleep 1 ;;
        esac
        [[ "$choice" != "b" && "$choice" != "B" ]] && wait_for_enter
    done
    disable_graceful_ctrlc
}
