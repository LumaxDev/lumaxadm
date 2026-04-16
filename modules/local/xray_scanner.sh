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

# --- Детальный анализ конкретного IP ---

_xrs_investigate_ip() {
    local port="$1"
    clear
    menu_header "🔍 Расследование IP"

    local target_ip
    target_ip=$(ask_non_empty "Введи IP для расследования") || return

    if ! validate_ip "$target_ip"; then
        err "Некорректный IP, братан."
        return
    fi

    echo ""
    print_separator "═" 64
    printf "  ${C_BOLD}${C_CYAN}🔍 ДОСЬЕ НА ${target_ip}${C_RESET}\n"
    print_separator "═" 64

    # 1. Количество соединений прямо сейчас
    local conn_count
    conn_count=$(ss -nt "( sport = :${port} )" 2>/dev/null | grep "$target_ip" | wc -l)

    echo ""
    printf "  ${C_WHITE}TCP-соединений сейчас:${C_RESET}  ${C_BOLD}${conn_count}${C_RESET}"
    if [[ "$conn_count" -ge "$_XRS_DANGER_THRESHOLD" ]]; then
        printf "  ${C_RED}🔴 ОПАСНО${C_RESET}"
    elif [[ "$conn_count" -ge "$_XRS_WARN_THRESHOLD" ]]; then
        printf "  ${C_YELLOW}🟡 Подозрительно${C_RESET}"
    else
        printf "  ${C_GREEN}🟢 Норма${C_RESET}"
    fi
    echo ""

    # 2. На какие хосты ходит (из access.log ноды)
    local access_log="/var/log/remnanode/access.log"
    local has_logs=0

    if [[ -f "$access_log" ]]; then
        has_logs=1
    elif command -v docker &>/dev/null; then
        local node_container
        node_container=$(docker ps --format '{{.Names}}' 2>/dev/null | grep "remnanode" | head -1)
        if [[ -n "$node_container" ]]; then
            # Вытаскиваем логи из контейнера во временный файл
            docker exec "$node_container" cat /var/log/remnanode/access.log > /tmp/_xrs_access_log_$$ 2>/dev/null
            if [[ -s /tmp/_xrs_access_log_$$ ]]; then
                access_log="/tmp/_xrs_access_log_$$"
                has_logs=1
            fi
        fi
    fi

    if [[ $has_logs -eq 1 ]]; then
        echo ""
        print_separator "─" 64
        printf "  ${C_BOLD}${C_YELLOW}🌐 КУДА ХОДИТ (топ-15 хостов)${C_RESET}\n"
        print_separator "─" 64
        echo ""

        local destinations
        destinations=$(grep "$target_ip" "$access_log" 2>/dev/null \
            | grep -oE 'accepted (tcp|udp):[^ ]+' \
            | sed 's/accepted [a-z]*://' \
            | cut -d: -f1 \
            | sort | uniq -c | sort -nr | head -15)

        if [[ -n "$destinations" ]]; then
            printf "  ${C_GRAY}%-8s %s${C_RESET}\n" "ЗАПР." "ХОСТ"
            print_separator "─" 64
            echo "$destinations" | while read -r count host; do
                local flag=""
                # Детект подозрительных паттернов
                if echo "$host" | grep -qiE "torrent|tracker|announce|peer"; then
                    flag="${C_RED} ⚠️ ТОРРЕНТ${C_RESET}"
                elif echo "$host" | grep -qiE "\.ru$|\.ru:|yandex|mail\.ru|vk\.com"; then
                    flag="${C_GRAY} (RU)${C_RESET}"
                elif echo "$host" | grep -qiE "google|youtube|gstatic|googleapis"; then
                    flag="${C_GRAY} (Google)${C_RESET}"
                elif echo "$host" | grep -qiE "facebook|instagram|meta|fbcdn"; then
                    flag="${C_GRAY} (Meta)${C_RESET}"
                elif echo "$host" | grep -qiE "tiktok|musical\.ly|bytedance"; then
                    flag="${C_GRAY} (TikTok)${C_RESET}"
                elif echo "$host" | grep -qiE "xiaomi|miui|intl\.xiaomi"; then
                    flag="${C_YELLOW} ⚠️ Xiaomi spam${C_RESET}"
                fi
                printf "  ${C_WHITE}%-8s${C_RESET} %s%b\n" "$count" "$host" "$flag"
            done
        else
            printf "  ${C_GRAY}Нет данных в логах для этого IP.${C_RESET}\n"
        fi

        # 3. Типы действий (BLOCK / IPv4 / DIRECT)
        echo ""
        print_separator "─" 64
        printf "  ${C_BOLD}${C_YELLOW}📊 ДЕЙСТВИЯ XRAY${C_RESET}\n"
        print_separator "─" 64
        echo ""

        local actions
        actions=$(grep "$target_ip" "$access_log" 2>/dev/null \
            | grep -oE '\[.*->.*\]|\[.*>>.*\]' \
            | sort | uniq -c | sort -nr)

        if [[ -n "$actions" ]]; then
            echo "$actions" | while read -r count action; do
                local action_color="${C_WHITE}"
                if echo "$action" | grep -q "BLOCK"; then
                    action_color="${C_RED}"
                elif echo "$action" | grep -q "DIRECT"; then
                    action_color="${C_YELLOW}"
                fi
                printf "  ${action_color}%-8s %s${C_RESET}\n" "$count" "$action"
            done
        else
            printf "  ${C_GRAY}Нет данных о действиях.${C_RESET}\n"
        fi

        # 4. Email (user ID) если есть
        echo ""
        print_separator "─" 64
        printf "  ${C_BOLD}${C_YELLOW}👤 ПОЛЬЗОВАТЕЛИ (email/ID)${C_RESET}\n"
        print_separator "─" 64
        echo ""

        local emails
        emails=$(grep "$target_ip" "$access_log" 2>/dev/null \
            | grep -oE 'email: [^ ]+' \
            | sed 's/email: //' \
            | sort | uniq -c | sort -nr | head -5)

        if [[ -n "$emails" ]]; then
            echo "$emails" | while read -r count email; do
                printf "  ${C_WHITE}%-8s${C_RESET} ID: ${C_CYAN}%s${C_RESET}\n" "$count" "$email"
            done
        else
            printf "  ${C_GRAY}Нет данных об email.${C_RESET}\n"
        fi

    else
        echo ""
        warn "Логи access.log не найдены. Настрой логи через Remnawave → Сменить путь логов."
        echo ""
        info "Без логов доступна только информация о соединениях."
    fi

    # 5. Вердикт
    echo ""
    print_separator "═" 64
    printf "  ${C_BOLD}🧠 ВЕРДИКТ${C_RESET}\n"
    print_separator "═" 64
    echo ""

    local verdict_score=0
    local verdicts=()

    # Много соединений
    if [[ "$conn_count" -ge "$_XRS_DANGER_THRESHOLD" ]]; then
        verdict_score=$((verdict_score + 3))
        verdicts+=("${C_RED}● ${conn_count} соединений — это дохуя${C_RESET}")
    elif [[ "$conn_count" -ge "$_XRS_WARN_THRESHOLD" ]]; then
        verdict_score=$((verdict_score + 1))
        verdicts+=("${C_YELLOW}● ${conn_count} соединений — многовато, но не критично${C_RESET}")
    else
        verdicts+=("${C_GREEN}● ${conn_count} соединений — в пределах нормы${C_RESET}")
    fi

    if [[ $has_logs -eq 1 ]]; then
        local total_requests
        total_requests=$(grep -c "$target_ip" "$access_log" 2>/dev/null | tr -dc '0-9')
        total_requests=${total_requests:-0}

        # --- Торренты (строгий паттерн: только реальные торрент-протоколы) ---
        local torrent_count
        torrent_count=$(grep "$target_ip" "$access_log" 2>/dev/null \
            | grep -ciE "torrent|\.tracker\.|/announce|bittorrent|bt\..*tracker" | tr -dc '0-9')
        torrent_count=${torrent_count:-0}
        if [[ "$torrent_count" -gt 5 ]]; then
            verdict_score=$((verdict_score + 3))
            verdicts+=("${C_RED}● Торрент-трафик: ${torrent_count} запросов к трекерам${C_RESET}")
        elif [[ "$torrent_count" -gt 0 ]]; then
            verdict_score=$((verdict_score + 1))
            verdicts+=("${C_YELLOW}● Возможный торрент: ${torrent_count} запросов (немного, может быть ложное)${C_RESET}")
        else
            verdicts+=("${C_GREEN}● Торрент-трафик не обнаружен${C_RESET}")
        fi

        # --- Процент BLOCK ---
        local block_count
        block_count=$(grep "$target_ip" "$access_log" 2>/dev/null | grep -c "BLOCK" | tr -dc '0-9')
        block_count=${block_count:-0}

        if [[ "$total_requests" -gt 0 ]]; then
            local block_pct=$(( (block_count * 100) / total_requests ))
            if [[ "$block_pct" -gt 70 ]]; then
                verdict_score=$((verdict_score + 2))
                verdicts+=("${C_RED}● ${block_pct}% запросов заблокировано — очень подозрительно${C_RESET}")
            elif [[ "$block_pct" -gt 30 ]]; then
                verdict_score=$((verdict_score + 1))
                verdicts+=("${C_YELLOW}● ${block_pct}% запросов заблокировано — повышенный уровень${C_RESET}")
            else
                verdicts+=("${C_GREEN}● Только ${block_pct}% заблокировано — норма${C_RESET}")
            fi
        fi

        # --- Разнообразие хостов (мало разных = бот, много = человек) ---
        local unique_hosts
        unique_hosts=$(grep "$target_ip" "$access_log" 2>/dev/null \
            | grep -oE 'accepted (tcp|udp):[^ ]+' | sed 's/accepted [a-z]*://' | cut -d: -f1 \
            | sort -u | wc -l)
        if [[ "$total_requests" -gt 100 && "$unique_hosts" -le 3 ]]; then
            verdict_score=$((verdict_score + 2))
            verdicts+=("${C_RED}● ${total_requests} запросов на всего ${unique_hosts} хоста — бот или DDoS${C_RESET}")
        elif [[ "$unique_hosts" -gt 20 ]]; then
            verdicts+=("${C_GREEN}● Ходит на ${unique_hosts} разных хостов — похоже на живого человека${C_RESET}")
        else
            verdicts+=("${C_WHITE}● Ходит на ${unique_hosts} хостов${C_RESET}")
        fi

        # --- Топ хост: DNS-резолверы не считаются ботом ---
        local top_host_line
        top_host_line=$(grep "$target_ip" "$access_log" 2>/dev/null \
            | grep -oE 'accepted (tcp|udp):[^ ]+' | sed 's/accepted [a-z]*://' | cut -d: -f1 \
            | sort | uniq -c | sort -nr | head -1)
        local top_host_count top_host_name
        top_host_count=$(echo "$top_host_line" | awk '{print $1}')
        top_host_name=$(echo "$top_host_line" | awk '{print $2}')

        # Исключаем DNS-резолверы и CDN из подозрений
        local is_normal_host=0
        if echo "$top_host_name" | grep -qE "^1\.1\.1\.|^8\.8\.[84]\.|^9\.9\.9\.|^1\.0\.0\.|dns|cloudflare|google\.com$"; then
            is_normal_host=1
        fi

        if [[ "${top_host_count:-0}" -gt 500 && $is_normal_host -eq 0 ]]; then
            verdict_score=$((verdict_score + 1))
            verdicts+=("${C_YELLOW}● Долбит ${top_host_name} ${top_host_count} раз${C_RESET}")
        elif [[ "${top_host_count:-0}" -gt 500 && $is_normal_host -eq 1 ]]; then
            verdicts+=("${C_GREEN}● Топ хост: ${top_host_name} (${top_host_count}×) — это DNS/CDN, нормально${C_RESET}")
        fi

        # --- Скорость запросов (запросов в минуту из последних записей) ---
        local first_ts last_ts
        first_ts=$(grep "$target_ip" "$access_log" 2>/dev/null | head -1 | grep -oE '^[0-9]{4}/[0-9]{2}/[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}')
        last_ts=$(grep "$target_ip" "$access_log" 2>/dev/null | tail -1 | grep -oE '^[0-9]{4}/[0-9]{2}/[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}')

        if [[ -n "$first_ts" && -n "$last_ts" && "$first_ts" != "$last_ts" ]]; then
            local first_epoch last_epoch
            first_epoch=$(date -d "${first_ts//\//-}" +%s 2>/dev/null || echo 0)
            last_epoch=$(date -d "${last_ts//\//-}" +%s 2>/dev/null || echo 0)
            local time_span=$(( last_epoch - first_epoch ))

            if [[ "$time_span" -gt 0 ]]; then
                local rpm=$(( (total_requests * 60) / time_span ))
                if [[ "$rpm" -gt 100 ]]; then
                    verdict_score=$((verdict_score + 2))
                    verdicts+=("${C_RED}● Скорость: ~${rpm} запросов/мин — агрессивный флуд${C_RESET}")
                elif [[ "$rpm" -gt 30 ]]; then
                    verdict_score=$((verdict_score + 1))
                    verdicts+=("${C_YELLOW}● Скорость: ~${rpm} запросов/мин — высокая активность${C_RESET}")
                else
                    verdicts+=("${C_GREEN}● Скорость: ~${rpm} запросов/мин — нормально${C_RESET}")
                fi
            fi
        fi

        # --- Подозрительные паттерны в хостах ---
        local scan_count
        scan_count=$(grep "$target_ip" "$access_log" 2>/dev/null \
            | grep -ciE "\.onion|proxy|socks|hack|exploit|shell|phish|malware|botnet|c2\." | tr -dc '0-9')
        scan_count=${scan_count:-0}
        if [[ "$scan_count" -gt 0 ]]; then
            verdict_score=$((verdict_score + 3))
            verdicts+=("${C_RED}● Обращения к подозрительным хостам (${scan_count}×): возможно malware/C2${C_RESET}")
        fi
    fi

    for v in "${verdicts[@]}"; do
        printf "  %b\n" "$v"
    done

    echo ""
    if [[ $verdict_score -ge 4 ]]; then
        printf "  ${C_BOLD}${C_RED}⛔ РЕКОМЕНДАЦИЯ: Этот IP стоит заблочить. Похоже на абуз или DDoS.${C_RESET}\n"
    elif [[ $verdict_score -ge 2 ]]; then
        printf "  ${C_BOLD}${C_YELLOW}⚠️  РЕКОМЕНДАЦИЯ: Подозрительная активность. Стоит последить.${C_RESET}\n"
    elif [[ $verdict_score -ge 1 ]]; then
        printf "  ${C_BOLD}${C_WHITE}ℹ️  Мелкие зацепки, но скорее всего нормальный юзер.${C_RESET}\n"
    else
        printf "  ${C_BOLD}${C_GREEN}✅ Чистый юзер. Никаких подозрений.${C_RESET}\n"
    fi

    # Чистим временные файлы
    rm -f /tmp/_xrs_access_log_$$
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
        printf_menu_option "3" "🔍 Расследование IP (досье, сайты, вердикт)"
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
            3)
                if [[ -z "$xray_port" ]]; then
                    warn "Порт не определён. Укажи через [p]."
                else
                    _xrs_investigate_ip "$xray_port"
                fi
                wait_for_enter
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
