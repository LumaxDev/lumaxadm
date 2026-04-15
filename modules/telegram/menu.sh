#!/bin/bash
#
# menu.sh - Мастер настройки уведомлений в Telegram
#
#   ( РОДИТЕЛЬ | КЛАВИША | НАЗВАНИЕ | ФУНКЦИЯ | ПОРЯДОК | ГРУППА | ОПИСАНИЕ )
# @menu.manifest
#
# @item( main | t | 📱 Уведомления в Telegram ${C_RED}(В разаработке)${C_RESET} | show_telegram_menu | 60 | 4 | Настройка уведомлений и интерактивного Telegram-бота. )
#
# @item( telegram | 1 | 🔑 Настроить API Token бота | _telegram_setup_token_wrapper | 10 | 1 | )
# @item( telegram | 2 | 📮 Управление адресатами | _telegram_manage_destinations | 20 | 1 | Настройка чатов и топиков для разных типов уведомлений. )
# @item( telegram | 3 | 🔔 Типы уведомлений | _telegram_manage_notifications | 30 | 1 | Включение и выключение отдельных категорий уведомлений. )
# @item( telegram | 4 | 🤖 Управление процессом бота | _telegram_bot_management | 40 | 2 | Запуск/остановка фонового процесса Telegram-бота. )
# @item( telegram | 5 | ✅ Отправить тестовое сообщение | _telegram_send_test_wrapper | 50 | 2 | )
# @item( telegram | d | 🆑 Отключить все уведомления | _telegram_disable_wrapper | 90 | 9 | Удаляет все настройки Telegram (токен, адресатов). )
#
# @item( telegram_destinations | 1 | Добавить / Изменить адресата | _telegram_add_edit_destination | 10 | 1 | )
# @item( telegram_destinations | 2 | Удалить адресата | _telegram_delete_destination | 20 | 1 | )
#

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1 # Защита от прямого запуска

# Подключаем общие зависимости и компоненты
source "${SCRIPT_DIR}/modules/core/common.sh"
source "${SCRIPT_DIR}/modules/telegram/core.sh"
source "${SCRIPT_DIR}/modules/telegram/bot.sh"

# ============================================================ #
#                         ДЕЙСТВИЯ МЕНЮ                        #
# ============================================================ #

_telegram_setup_token_wrapper() {
    print_separator; info "Настройка API Token"; print_separator
    printf_description "Создайте бота у @BotFather в Telegram, чтобы получить токен."
    local new_token; new_token=$(ask_non_empty "Введите новый Bot Token") || return
    set_config_var "TG_BOT_TOKEN" "$new_token"; ok "API Token сохранен."
    wait_for_enter
}

_telegram_send_test_wrapper() {
    print_separator; info "Отправка тестового сообщения"; print_separator
    local destinations; destinations=$(_telegram_get_destinations)
    if [[ -z "$destinations" ]]; then err "Не настроено ни одного адресата для отправки."; wait_for_enter; return; fi
    info "Выберите, куда отправить тест:"; local dest_choice_idx; dest_choice_idx=$(ask_selection "" $destinations) || return
    local i=1; local dest_name=""; for dest in $destinations; do if [[ $i -eq $dest_choice_idx ]]; then dest_name=$dest; break; fi; ((i++)); done
    local hostname; hostname=$(hostname -f)
    local message="🧪 *Тестовое сообщение от LumaxADM*\n\nАдресат: \`$dest_name`\nСервер: \`$hostname`\nВремя: \`$(date '+%Y-%m-%d %H:%M:%S')`\n\nВсе работает отлично! 👍"
    info "Отправляю сообщение адресату '$dest_name'வுகளை..."
    if tg_notify "$dest_name" "$message"; then ok "Тестовое сообщение успешно отправлено!"; else err "Ошибка отправки. Проверьте токен, ID и лог."; fi
    wait_for_enter
}

_telegram_disable_wrapper() {
    if ask_yes_no "Вы уверены, что хотите удалить ВСЕ настройки Telegram (токен и адресатов)?"; then
        local keys_to_delete; keys_to_delete=$(grep "^TG_" "${SCRIPT_DIR}/config/lumaxadm.conf" | cut -d'=' -f1)
        for key in $keys_to_delete; do sed -i "/^${key}=/d" "${SCRIPT_DIR}/config/lumaxadm.conf" 2>/dev/null || true; done
        ok "Все настройки Telegram удалены."
    fi
    wait_for_enter
}

_telegram_add_edit_destination() {
    info "Добавление/изменение адресата"
    local dest_name; dest_name=$(ask_non_empty "Введите имя адресата (напр. DEFAULT, FAIL2BAN)") || return
    local upper_dest_name; upper_dest_name=$(echo "$dest_name" | tr '[:lower:]' '[:upper:]')
    local chat_id; chat_id=$(ask_non_empty "Введите Chat ID для '$upper_dest_name'") || return
    local topic_id; topic_id=$(safe_read "Введите Topic ID для '$upper_dest_name' (если нужно)" "") || return
    set_config_var "TG_CHAT_ID_${upper_dest_name}" "$chat_id"
    set_config_var "TG_TOPIC_ID_${upper_dest_name}" "${topic_id:-0}"
    ok "Адресат '$upper_dest_name' сохранен."; wait_for_enter
}

_telegram_delete_destination() {
    info "Удаление адресата"; local destinations; destinations=$(_telegram_get_destinations)
    if [[ -z "$destinations" ]]; then warn "Нет адресатов для удаления."; wait_for_enter; return; fi
    local dest_to_del_idx; dest_to_del_idx=$(ask_selection "Выберите адресата для удаления:" $destinations) || return
    local i=1; local dest_name=""; for dest in $destinations; do if [[ $i -eq $dest_to_del_idx ]]; then dest_name=$dest; break; fi; ((i++)); done
    if [[ "$dest_name" == "DEFAULT" ]]; then warn "Адресата DEFAULT нельзя удалить."; wait_for_enter; return; fi
    if ask_yes_no "Вы уверены, что хотите удалить адресата '$dest_name'?"; then
        sed -i "/^TG_CHAT_ID_${dest_name}=/d" "${SCRIPT_DIR}/config/lumaxadm.conf"
        sed -i "/^TG_TOPIC_ID_${dest_name}=/d" "${SCRIPT_DIR}/config/lumaxadm.conf"
        ok "Адресат '$dest_name' удален."
    fi; wait_for_enter
}

_telegram_toggle_ssh_notify() {
    local is_enabled=false; if [[ -f "/etc/ssh/lumaxadm-notify-login.sh" ]]; then is_enabled=true; fi
    local action="enable"; local action_text="включить"; if [[ "$is_enabled" == true ]]; then action="disable"; action_text="отключить"; fi
    if ! ask_yes_no "Вы уверены, что хотите ${action_text} уведомления о входе по SSH?"; then info "Отмена."; wait_for_enter; return; fi
    local chat_id=""; if [[ "$action" == "enable" ]]; then
        local destinations; destinations=$(_telegram_get_destinations); if [[ -z "$destinations" ]]; then err "Сначала настройте адресата."; wait_for_enter; return; fi
        info "Выберите адресата для этих уведомлений:"; local dest_choice_idx; dest_choice_idx=$(ask_selection "" $destinations) || return
        local i=1; local dest_name=""; for dest in $destinations; do if [[ $i -eq $dest_choice_idx ]]; then dest_name=$dest; break; fi; ((i++)); done
        chat_id=$(get_config_var "TG_CHAT_ID_${dest_name}")
    fi
    local token; token=$(get_config_var "TG_BOT_TOKEN"); if [[ -z "$token" ]]; then err "API Token не настроен."; wait_for_enter; return; fi
    info "Применяю изменения..."; export TG_BOT_TOKEN="$token"; export TG_CHAT_ID="$chat_id"
    if ! bash "${SCRIPT_DIR}/plugins/skynet_commands/security/06_setup_ssh_login_notify.sh" "$action"; then err "Произошла ошибка."; else ok "Настройки успешно применены."; fi
    unset TG_BOT_TOKEN; unset TG_CHAT_ID; wait_for_enter
}

# ============================================================ #
#                         ФУНКЦИИ МЕНЮ                         #
# ============================================================ #

_telegram_get_destinations() { grep "^TG_CHAT_ID_" "${SCRIPT_DIR}/config/lumaxadm.conf" | sed 's/TG_CHAT_ID_//;s/=".*"//'; }

_telegram_bot_management() {
    enable_graceful_ctrlc; while true; do
        clear; menu_header "🤖 Управление процессом бота"; handle_bot_process "status"; print_separator
        printf_menu_option "1" "Запустить бота"; printf_menu_option "2" "Остановить бота"; echo ""; printf_menu_option "b" "Назад"; echo ""
        local choice; choice=$(safe_read "Выберите действие" "") || break
        case "$choice" in
            1) handle_bot_process "start"; wait_for_enter;; 2) handle_bot_process "stop"; wait_for_enter;; 
            b|B) break;; *) warn "Неверный выбор";;
        esac
    done; disable_graceful_ctrlc
}

_telegram_manage_notifications() {
    enable_graceful_ctrlc; while true; do
        clear; menu_header "🔔 Типы Уведомлений"; printf_description "Включение и выключение отдельных категорий уведомлений."; print_separator
        local ssh_notify_status="${C_RED}Выключено${C_RESET}"; if [[ -f "/etc/ssh/lumaxadm-notify-login.sh" ]]; then ssh_notify_status="${C_GREEN}Включено${C_RESET}"; fi
        printf_menu_option "1" "Уведомления о входе по SSH ...... [ ${ssh_notify_status} ]"
        echo ""; printf_menu_option "b" "Назад"; echo ""
        local choice; choice=$(safe_read "Выберите действие" "") || break
        case "$choice" in
            1) _telegram_toggle_ssh_notify;; 
            b|B) break;; *) warn "Неверный выбор";;
        esac
    done; disable_graceful_ctrlc
}

_telegram_manage_destinations() {
    enable_graceful_ctrlc; while true; do
        clear; menu_header "📮 Управление адресатами"; printf_description "Настройка чатов и топиков для разных типов уведомлений."; print_separator
        info "Текущие адресаты:"
        local destinations; destinations=$(_telegram_get_destinations)
        if [[ -z "$destinations" ]]; then warn "Ни одного адресата не настроено."; else
            for dest in $destinations; do
                local chat_id; chat_id=$(get_config_var "TG_CHAT_ID_${dest}")
                local topic_id; topic_id=$(get_config_var "TG_TOPIC_ID_${dest}")
                local display_name="$dest"; [[ "$dest" == "DEFAULT" ]] && display_name="DEFAULT (По умолчанию)"
                if [[ -n "$topic_id" && "$topic_id" -ne 0 ]]; then printf_description "  • ${C_WHITE}${display_name}${C_RESET} → Чат: ${C_CYAN}${chat_id}${C_RESET}, Топик: ${C_CYAN}${topic_id}${C_RESET}"; else printf_description "  • ${C_WHITE}${display_name}${C_RESET} → Чат: ${C_CYAN}${chat_id}${C_RESET}"; fi
            done
        fi
        print_separator
        render_menu_items "telegram_destinations"
        echo ""; printf_menu_option "b" "Назад"; echo ""
        local choice; choice=$(safe_read "Выберите действие" "") || break
        if [[ "$choice" == "b" || "$choice" == "B" ]]; then break; fi
        local action; action=$(get_menu_action "telegram_destinations" "$choice")
        if [[ -n "$action" ]]; then eval "$action"; else warn "Неверный выбор"; fi
    done; disable_graceful_ctrlc
}

show_telegram_menu() {
    enable_graceful_ctrlc; while true; do
        clear; menu_header "📱 Уведомления Telegram"; printf_description "Настройка уведомлений и интерактивного бота."; print_separator
        local token; token=$(get_config_var "TG_BOT_TOKEN")
        if [[ -n "$token" ]]; then ok "API Token бота настроен."; else warn "API Token бота не настроен. Это первый шаг."; fi
        print_separator; render_menu_items "telegram"; echo ""; printf_menu_option "b" "Назад"; echo ""
        local choice; choice=$(safe_read "Выберите действие" "") || break
        if [[ "$choice" == "b" || "$choice" == "B" ]]; then break; fi
        local action; action=$(get_menu_action "telegram" "$choice")
        if [[ -n "$action" ]]; then eval "$action"; else warn "Неверный выбор"; fi
    done; disable_graceful_ctrlc
}
