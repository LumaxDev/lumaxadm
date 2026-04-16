#!/bin/bash
# ============================================================ #
# ==         МОДУЛЬ «РЕНТГЕН XRAY» — АНАЛИЗ ПОДКЛЮЧЕНИЙ     == #
# ============================================================ #
#
#  ( РОДИТЕЛЬ | КЛАВИША | НАЗВАНИЕ | ФУНКЦИЯ | ПОРЯДОК | ГРУППА | ОПИСАНИЕ )
# @menu.manifest
# (подключается вручную из diagnostics.sh, без манифеста в main)
#
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1

# Порог подключений, выше которого IP считается подозрительным
readonly _XRS_WARN_THRESHOLD=500
readonly _XRS_DANGER_THRESHOLD=2000

# --- Определение порта Xray ---

_xrs_detect_xray_port() {
    local xray_port

    # Способ 1: ищем процесс rw-core (Remnawave node) — публичный порт (не 127.0.0.1)
    xray_port=$(ss -tlnp 2>/dev/null | grep "rw-core" | grep -v "127.0.0.1" | awk '{print $4}' | grep -oE '[0-9]+$' | head -1)
    if [[ -n "$xray_port" ]]; then
        echo "$xray_port"
        return 0
    fi

    # Способ 2: ищем процесс xray напрямую
    xray_port=$(ss -tlnp 2>/dev/null | grep -i "xray" | grep -v "127.0.0.1" | awk '{print $4}' | grep -oE '[0-9]+$' | head -1)
    if [[ -n "$xray_port" ]]; then
        echo "$xray_port"
        return 0
    fi

    # Способ 3: проверяем 443 — стандартный порт для VLESS/Reality
    if ss -tlnp 2>/dev/null | grep -q ":443 "; then
        echo "443"
        return 0
    fi

    return 1
}

# --- Сбор данных ---

_xrs_get_connections() {
    local port="$1"
    ss -nt "( sport = :${port} )" 2>/dev/null \
        | awk 'NR>1 {print $5}' \
        | sed -E 's/^\[::ffff:([0-9.]+)\]:[0-9]+$/\1/; s/^\[([0-9a-fA-F:]+)\]:[0-9]+$/\1/; s/:([0-9]+)$//' \
        | sort | uniq -c | sort -nr
}

# --- Красивый вывод ---

_xrs_show_report() {
    local port="$1"

    local total_conns
    total_conns=$(ss -nt "( sport = :${port} )" 2>/dev/null | tail -n +2 | wc -l)

    local unique_ips
    unique_ips=$(_xrs_get_connections "$port" | wc -l)

    echo ""
    print_separator "═" 64
    printf "  ${C_BOLD}${C_CYAN}🔬 РЕНТГЕН XRAY — ПОРТ ${port}${C_RESET}\n"
    print_separator "═" 64
    echo ""

    printf "  ${C_WHITE}Всего соединений:${C_RESET}  ${C_BOLD}${total_conns}${C_RESET}\n"
    printf "  ${C_WHITE}Уникальных IP:${C_RESET}     ${C_BOLD}${unique_ips}${C_RESET}\n"
    echo ""

    if [[ "$total_conns" -eq 0 ]]; then
        info "Тишина. Ни одного подключения. Либо всё мирно, либо Xray лежит."
        return
    fi

    # Топ-20 IP
    print_separator "─" 64
    printf "  ${C_BOLD}${C_YELLOW}📊 ТОП-20 IP ПО КОЛИЧЕСТВУ СОЕДИНЕНИЙ${C_RESET}\n"
    print_separator "─" 64
    echo ""
    printf "  ${C_GRAY}%-10s %-22s %s${C_RESET}\n" "КОНН." "IP-АДРЕС" "СТАТУС"
    print_separator "─" 64

    local suspicious_ips=()
    local danger_ips=()

    _xrs_get_connections "$port" | head -20 | while read -r count ip; do
        local status_icon status_color

        if [[ "$count" -ge "$_XRS_DANGER_THRESHOLD" ]]; then
            status_icon="🔴 ОПАСНО"
            status_color="${C_RED}"
            echo "$ip" >> /tmp/_xrs_danger_$$
        elif [[ "$count" -ge "$_XRS_WARN_THRESHOLD" ]]; then
            status_icon="🟡 Подозр."
            status_color="${C_YELLOW}"
            echo "$ip" >> /tmp/_xrs_suspect_$$
        else
            status_icon="🟢 Норма"
            status_color="${C_GREEN}"
        fi

        printf "  ${status_color}%-10s${C_RESET} ${C_WHITE}%-22s${C_RESET} ${status_color}%s${C_RESET}\n" "$count" "$ip" "$status_icon"
    done

    echo ""

    # Собираем подозрительные IP из временных файлов
    local has_danger=0
    local has_suspect=0
    [[ -f /tmp/_xrs_danger_$$ ]] && has_danger=1
    [[ -f /tmp/_xrs_suspect_$$ ]] && has_suspect=1

    if [[ $has_danger -eq 1 ]]; then
        print_separator "═" 64
        printf "  ${C_BOLD}${C_RED}⚠️  ОБНАРУЖЕНЫ АНОМАЛИИ${C_RESET}\n"
        print_separator "═" 64
        echo ""
        printf "  ${C_RED}Эти IP держат ${_XRS_DANGER_THRESHOLD}+ соединений — похоже на DDoS или абуз:${C_RESET}\n"
        echo ""
        while read -r ip; do
            local conns
            conns=$(_xrs_get_connections "$port" | awk -v ip="$ip" '$2==ip {print $1}')
            printf "  ${C_RED}  ● ${C_BOLD}%-18s${C_RESET} ${C_RED}(%s соединений)${C_RESET}\n" "$ip" "$conns"
        done < /tmp/_xrs_danger_$$
        echo ""
        warn "Рекомендация: заблочить через [b] в этом меню или вручную через UFW."
    elif [[ $has_suspect -eq 1 ]]; then
        echo ""
        warn "Есть подозрительные IP (${_XRS_WARN_THRESHOLD}+ соединений). Пока не критично, но стоит следить."
    else
        echo ""
        ok "Всё чисто, братан. Аномалий не обнаружено."
    fi

    # Чистим временные файлы
    rm -f /tmp/_xrs_danger_$$ /tmp/_xrs_suspect_$$
}

# --- Блокировка IP ---

_xrs_block_ip() {
    local port="$1"

    # Собираем опасные IP
    local danger_list=()
    local data
    data=$(_xrs_get_connections "$port" | awk -v threshold="$_XRS_DANGER_THRESHOLD" '$1 >= threshold {print $2, $1}')

    if [[ -z "$data" ]]; then
        # Нет опасных — предлагаем ввести вручную
        info "Автоматически опасных IP не обнаружено (порог: ${_XRS_DANGER_THRESHOLD}+ соединений)."
        echo ""
        local manual_ip
        manual_ip=$(safe_read "Введи IP для блокировки вручную (или Enter для отмены)" "") || return
        if [[ -z "$manual_ip" ]]; then return; fi
        if ! validate_ip "$manual_ip"; then
            err "Некорректный IP."
            return
        fi
        if ask_yes_no "Заблочить ${manual_ip} через UFW?"; then
            run_cmd ufw deny from "$manual_ip" comment "LumaxADM Xray block"
            ok "IP ${manual_ip} заблокирован."
        fi
        return
    fi

    # Показываем список опасных
    echo ""
    print_separator "─" 64
    printf "  ${C_BOLD}${C_RED}🎯 IP НА БЛОКИРОВКУ (${_XRS_DANGER_THRESHOLD}+ соединений):${C_RESET}\n"
    print_separator "─" 64
    echo ""

    local ips_to_block=()
    while read -r ip conns; do
        printf "  ${C_RED}● ${C_BOLD}%-18s${C_RESET} ${C_GRAY}(%s соединений)${C_RESET}\n" "$ip" "$conns"
        ips_to_block+=("$ip")
    done <<< "$data"

    echo ""

    if ! command -v ufw &>/dev/null; then
        warn "UFW не установлен. Заблокировать не получится."
        info "Можешь заблочить вручную через iptables:"
        for ip in "${ips_to_block[@]}"; do
            printf_description "iptables -I INPUT -s ${ip} -j DROP"
        done
        return
    fi

    printf_menu_option "1" "Заблочить ВСЕ (${#ips_to_block[@]} шт.)"
    printf_menu_option "2" "Выбрать конкретные"
    printf_menu_option "b" "Не блочить"
    echo ""

    local choice
    choice=$(safe_read "Что делаем?" "") || return

    case "$choice" in
        1)
            if ask_yes_no "Точно заблочить все ${#ips_to_block[@]} IP?"; then
                for ip in "${ips_to_block[@]}"; do
                    run_cmd ufw deny from "$ip" comment "LumaxADM Xray block"
                    ok "Заблочен: ${ip}"
                done
                run_cmd ufw reload
                ok "Готово! ${#ips_to_block[@]} IP заблокировано."
            fi
            ;;
        2)
            for ip in "${ips_to_block[@]}"; do
                local conns
                conns=$(echo "$data" | awk -v ip="$ip" '$1==ip {print $2}')
                if ask_yes_no "Заблочить ${ip} (${conns} соединений)?"; then
                    run_cmd ufw deny from "$ip" comment "LumaxADM Xray block"
                    ok "Заблочен: ${ip}"
                fi
            done
            run_cmd ufw reload
            ok "Готово!"
            ;;
        b|B) info "Ладно, не блочим." ;;
        *) warn "Нет такого пункта." ;;
    esac
}

# --- Авто-режим (быстрый скан) ---

_xrs_quick_scan() {
    local port="$1"
    clear
    menu_header "🔬 Быстрый скан Xray"
    _xrs_show_report "$port"
}

# --- Мониторинг (обновляется каждые N секунд) ---

_xrs_live_monitor() {
    local port="$1"
    info "Мониторинг подключений (обновление каждые 5 сек, CTRL+C для выхода)"
    echo ""

    enable_graceful_ctrlc
    while true; do
        clear
        local total
        total=$(ss -nt "( sport = :${port} )" 2>/dev/null | tail -n +2 | wc -l)

        printf "  ${C_BOLD}${C_CYAN}🔬 LIVE МОНИТОР — ПОРТ ${port}${C_RESET}  |  "
        printf "${C_WHITE}Соединений: ${C_BOLD}${total}${C_RESET}  |  "
        printf "${C_GRAY}$(date '+%H:%M:%S')${C_RESET}\n"
        print_separator "─" 64
        printf "  ${C_GRAY}%-10s %-22s %s${C_RESET}\n" "КОНН." "IP-АДРЕС" "СТАТУС"
        print_separator "─" 64

        _xrs_get_connections "$port" | head -15 | while read -r count ip; do
            local status_icon status_color
            if [[ "$count" -ge "$_XRS_DANGER_THRESHOLD" ]]; then
                status_icon="🔴 ОПАСНО"
                status_color="${C_RED}"
            elif [[ "$count" -ge "$_XRS_WARN_THRESHOLD" ]]; then
                status_icon="🟡 Подозр."
                status_color="${C_YELLOW}"
            else
                status_icon="🟢 Норма"
                status_color="${C_GREEN}"
            fi
            printf "  ${status_color}%-10s${C_RESET} ${C_WHITE}%-22s${C_RESET} ${status_color}%s${C_RESET}\n" "$count" "$ip" "$status_icon"
        done

        print_separator "─" 64
        printf "  ${C_GRAY}CTRL+C для выхода${C_RESET}\n"

        sleep 5 || break
    done
    disable_graceful_ctrlc
}

# --- Главное меню ---

show_xray_scanner_menu() {
    # Определяем порт
    local xray_port
    xray_port=$(_xrs_detect_xray_port)

    enable_graceful_ctrlc
    while true; do
        clear
        menu_header "🔬 Рентген Xray"

        if [[ -z "$xray_port" ]]; then
            printf_description "Xray не обнаружен на этом сервере."
            printf_description "${C_GRAY}Если Xray слушает на нестандартном порту — укажи вручную.${C_RESET}"
        else
            printf_description "Xray обнаружен на порту: ${C_GREEN}${xray_port}${C_RESET}"
            local total
            total=$(ss -nt "( sport = :${xray_port} )" 2>/dev/null | tail -n +2 | wc -l)
            printf_description "Активных соединений: ${C_CYAN}${total}${C_RESET}"
        fi

        echo ""
        printf_menu_option "1" "📊 Полный отчёт (топ IP, аномалии)"
        printf_menu_option "2" "📡 Live-мониторинг (обновление каждые 5 сек)"
        printf_menu_option "p" "🔧 Указать порт вручную"
        echo ""
        printf_menu_option "b" "Назад"
        echo ""

        local choice
        choice=$(safe_read "Что смотрим?" "") || break

        case "$choice" in
            1)
                if [[ -z "$xray_port" ]]; then
                    warn "Порт не определён. Укажи через [p]."
                else
                    clear
                    _xrs_show_report "$xray_port"
                fi
                wait_for_enter
                ;;
            2)
                if [[ -z "$xray_port" ]]; then
                    warn "Порт не определён. Укажи через [p]."
                    wait_for_enter
                else
                    _xrs_live_monitor "$xray_port"
                fi
                ;;
            p|P)
                local new_port
                new_port=$(ask_number_in_range "Введи порт Xray" 1 65535) || continue
                xray_port="$new_port"
                ok "Порт установлен: ${xray_port}"
                sleep 1
                ;;
            b|B) break ;;
            *) warn "Нет такого пункта." && sleep 1 ;;
        esac
    done
    disable_graceful_ctrlc
}
