#!/bin/bash
# ============================================================ #
# ==           UPDATER: МЕНЕДЖЕР КОНФИГУРАЦИИ               == #
# ============================================================ #

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1 # Защита от прямого запуска

UPDATER_CONF="${SCRIPT_DIR}/config/updater.conf"

# Инициализация конфига
init_updater_config() {
    if [ ! -f "$UPDATER_CONF" ]; then
        touch "$UPDATER_CONF"
        # Формат: PATH|STRATEGY|LABEL
        echo "# PATH|STRATEGY|LABEL" > "$UPDATER_CONF"
    fi
}

# Чтение сервисов в массивы
declare -a UPDATER_PATHS=()
declare -a UPDATER_STRATEGIES=()
declare -a UPDATER_LABELS=()

load_updater_config() {
    init_updater_config
    UPDATER_PATHS=()
    UPDATER_STRATEGIES=()
    UPDATER_LABELS=()

    while IFS='|' read -r path strategy label; do
        [[ -z "$path" || "$path" == \#* ]] && continue
        UPDATER_PATHS+=("$path")
        UPDATER_STRATEGIES+=("$strategy")
        UPDATER_LABELS+=("$label")
    done < "$UPDATER_CONF"
}

save_updater_config() {
    echo "# PATH|STRATEGY|LABEL" > "$UPDATER_CONF"
    for i in "${!UPDATER_PATHS[@]}"; do
        echo "${UPDATER_PATHS[$i]}|${UPDATER_STRATEGIES[$i]}|${UPDATER_LABELS[$i]}" >> "$UPDATER_CONF"
    done
}

# Определение стратегии и метки по содержимому docker-compose.yml
detect_service_info() {
    local target_dir="$1"
    local compose_file="$target_dir/docker-compose.yml"
    if [ ! -f "$compose_file" ]; then compose_file="$target_dir/docker-compose.yaml"; fi

    local strategy="PULL_RESTART"
    local label="📦 НЕИЗВЕСТНЫЙ СЕРВИС"

    if [ -f "$compose_file" ]; then
        if grep -q "image:.*remnawave/node" "$compose_file"; then
            label="🚜 РАБОТЯГА (NODE)"
        elif grep -q "image:.*remnawave/backend" "$compose_file"; then
            label="👑 ПАХАН (PANEL)"
        elif grep -q -i "bedolaga" "$compose_file" || grep -q -i "bot" "$compose_file"; then
            label="🤖 BEDOLAGA / BOT"
            strategy="BUILD_RESTART"
        elif grep -q "nginx" "$compose_file"; then
            label="🌐 NGINX WEB"
        elif grep -q "certwarden" "$compose_file"; then
            label="🔐 CERTWARDEN"
        elif grep -q "build:" "$compose_file"; then
            label="🛠️ КАСТОМНАЯ СБОРКА"
            strategy="BUILD_RESTART"
        fi
    fi

    echo "${strategy}|${label}"
}

# Сканирование системы
scan_system_for_services() {
    printf_info "🔍 Начинаю сканирование системы (/opt и /root)... Это может занять пару секунд."

    local found_files
    mapfile -t found_files < <(find /opt /root -maxdepth 4 -name "docker-compose.y*ml" 2>/dev/null)

    if [ ${#found_files[@]} -eq 0 ]; then
        printf_warning "Ничего не найдено!"
        return
    fi

    local detected_paths=()
    local detected_strats=()
    local detected_labels=()

    for file in "${found_files[@]}"; do
        local dir
        dir=$(dirname "$file")

        # Пропускаем, если уже есть в текущем конфиге
        local exists=0
        for existing in "${UPDATER_PATHS[@]}"; do
            if [[ "$existing" == "$dir" ]]; then
                exists=1
                break
            fi
        done
        [[ $exists -eq 1 ]] && continue

        local info
        info=$(detect_service_info "$dir")
        local strat="${info%%|*}"
        local label="${info#*|}"

        detected_paths+=("$dir")
        detected_strats+=("$strat")
        detected_labels+=("$label")
    done

    if [ ${#detected_paths[@]} -eq 0 ]; then
        printf_ok "Все найденные сервисы уже добавлены в список обновления."
        return
    fi

    printf_info "Найдено новых сервисов: ${#detected_paths[@]}"
    for i in "${!detected_paths[@]}"; do
        printf "  %b[%d]%b %b%s%b (%s) -> %s\n" "${C_YELLOW}" "$((i+1))" "${C_RESET}" "${C_CYAN}" "${detected_paths[$i]}" "${C_RESET}" "${detected_labels[$i]}" "${detected_strats[$i]}"
    done

    echo ""
    local choice
    choice=$(ask_selection "Что делаем с найденными?" "Сохранить ВСЕ" "Выбрать вручную (по одному)" "Отмена") || return

    if [[ "$choice" == "1" ]]; then
        for i in "${!detected_paths[@]}"; do
            UPDATER_PATHS+=("${detected_paths[$i]}")
            UPDATER_STRATEGIES+=("${detected_strats[$i]}")
            UPDATER_LABELS+=("${detected_labels[$i]}")
        done
        save_updater_config
        printf_ok "Все сервисы добавлены в конфиг!"
    elif [[ "$choice" == "2" ]]; then
        for i in "${!detected_paths[@]}"; do
            if ask_yes_no "Добавить ${C_CYAN}${detected_paths[$i]}${C_RESET} [${detected_labels[$i]}]?" "y"; then
                UPDATER_PATHS+=("${detected_paths[$i]}")
                UPDATER_STRATEGIES+=("${detected_strats[$i]}")
                UPDATER_LABELS+=("${detected_labels[$i]}")
            fi
        done
        save_updater_config
        printf_ok "Выбранные сервисы сохранены!"
    fi
}

show_updater_config_menu() {
    while true; do
        load_updater_config
        clear
        menu_header "⚙️ НАСТРОЙКИ АВТООБНОВЛЯТОРА" 60 "${C_MAGENTA}"

        echo -e "  ${C_YELLOW}Текущие сервисы в очереди обновления:${C_RESET}"
        if [ ${#UPDATER_PATHS[@]} -eq 0 ]; then
            echo -e "  ${C_GRAY}Пусто. Запусти сканирование или добавь вручную.${C_RESET}"
        else
            for i in "${!UPDATER_PATHS[@]}"; do
                printf "  %b[%d]%b %-35s %b[%s]%b\n" "${C_YELLOW}" "$((i+1))" "${C_RESET}" "${UPDATER_PATHS[$i]}" "${C_GREEN}" "${UPDATER_STRATEGIES[$i]}" "${C_RESET}"
            done
        fi
        print_separator "─" 60

        printf_menu_option "1" "🔍 Авто-сканирование системы" "${C_GREEN}"
        printf_menu_option "2" "➕ Добавить сервис вручную"
        printf_menu_option "3" "🗑️ Удалить сервис"
        printf_menu_option "4" "🔄 Изменить стратегию сервиса"
        printf_menu_option "b" "🔙 Назад" "${C_CYAN}"

        print_separator "─" 60

        local choice
        choice=$(safe_read "Выбор" "") || return 130

        case "$choice" in
            1)
                scan_system_for_services
                wait_for_enter
                ;;
            2)
                local new_path
                new_path=$(ask_non_empty "Полный путь к папке с docker-compose (например, /opt/my_app):") || continue
                if [ ! -d "$new_path" ]; then
                    printf_error "Папка не существует!"
                    sleep 2
                    continue
                fi
                local strat_choice
                strat_choice=$(ask_selection "Выберите стратегию обновления:" "PULL_RESTART (Обычный pull + restart)" "BUILD_RESTART (git pull + build + restart)") || continue

                local strategy="PULL_RESTART"
                [[ "$strat_choice" == "2" ]] && strategy="BUILD_RESTART"

                local info
                info=$(detect_service_info "$new_path")
                local label="${info#*|}"

                UPDATER_PATHS+=("$new_path")
                UPDATER_STRATEGIES+=("$strategy")
                UPDATER_LABELS+=("$label")
                save_updater_config
                printf_ok "Сервис добавлен!"
                sleep 1
                ;;
            3)
                if [ ${#UPDATER_PATHS[@]} -gt 0 ]; then
                    local idx
                    idx=$(ask_number_in_range "Введи номер для удаления (0 для отмены)" 0 "${#UPDATER_PATHS[@]}") || continue
                    if [[ "$idx" -gt 0 ]]; then
                        local real_idx=$((idx-1))
                        unset 'UPDATER_PATHS[real_idx]'
                        unset 'UPDATER_STRATEGIES[real_idx]'
                        unset 'UPDATER_LABELS[real_idx]'
                        UPDATER_PATHS=("${UPDATER_PATHS[@]}")
                        UPDATER_STRATEGIES=("${UPDATER_STRATEGIES[@]}")
                        UPDATER_LABELS=("${UPDATER_LABELS[@]}")
                        save_updater_config
                        printf_ok "Удалено!"
                        sleep 1
                    fi
                fi
                ;;
            4)
                if [ ${#UPDATER_PATHS[@]} -gt 0 ]; then
                    local idx
                    idx=$(ask_number_in_range "Введи номер для изменения (0 для отмены)" 0 "${#UPDATER_PATHS[@]}") || continue
                    if [[ "$idx" -gt 0 ]]; then
                        local real_idx=$((idx-1))
                        local current_strat="${UPDATER_STRATEGIES[real_idx]}"
                        if [[ "$current_strat" == "PULL_RESTART" ]]; then
                            UPDATER_STRATEGIES[real_idx]="BUILD_RESTART"
                        else
                            UPDATER_STRATEGIES[real_idx]="PULL_RESTART"
                        fi
                        save_updater_config
                        printf_ok "Стратегия изменена на ${UPDATER_STRATEGIES[real_idx]}!"
                        sleep 1
                    fi
                fi
                ;;
            b|B)
                break
                ;;
            *)
                printf_error "Неверный выбор."
                sleep 1
                ;;
        esac
    done
}
