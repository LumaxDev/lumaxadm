#!/bin/bash
# ============================================================ #
# ==             МОДУЛЬ «ЛОВЛЯ IP»                           == #
# ============================================================ #
#
#  ( РОДИТЕЛЬ | КЛАВИША | НАЗВАНИЕ | ФУНКЦИЯ | ПОРЯДОК | ГРУППА | ОПИСАНИЕ )
# @menu.manifest
# @item( main | 3 | 🎣 Ловля IP | show_ip_roller_menu | 25 | 2 | Прокрутка IP до попадания в whitelist операторов. )
#
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1

readonly _IPR_SCRIPT_URL="https://raw.githubusercontent.com/princeofscale/yacloud-ip-roller/main/roll_ip.py"
readonly _IPR_INSTALL_DIR="/opt/lumaxadm/tools/ip-roller"
readonly _IPR_SCRIPT_PATH="${_IPR_INSTALL_DIR}/roll_ip.py"

# --- Определение облачного провайдера ---

_ipr_detect_yandex() {
    # Способ 1: DMI (самый надёжный)
    if grep -qi "yandex" /sys/class/dmi/id/board_vendor 2>/dev/null; then
        return 0
    fi
    if grep -qi "yandex" /sys/class/dmi/id/sys_vendor 2>/dev/null; then
        return 0
    fi

    # Способ 2: metadata endpoint Яндекса
    local meta
    meta=$(curl -s --connect-timeout 3 --max-time 5 -H "Metadata-Flavor: Google" \
        "http://169.254.169.254/computeMetadata/v1/project/project-id" 2>/dev/null)
    if [[ -n "$meta" && "$meta" != *"404"* && "$meta" != *"error"* ]]; then
        return 0
    fi

    return 1
}

_ipr_get_instance_id() {
    local iid
    iid=$(curl -s --connect-timeout 3 --max-time 5 -H "Metadata-Flavor: Google" \
        "http://169.254.169.254/computeMetadata/v1/instance/id" 2>/dev/null)
    if [[ -n "$iid" && "$iid" != *"404"* && "$iid" != *"error"* ]]; then
        echo "$iid"
        return 0
    fi
    return 1
}

# --- Установка зависимостей ---

_ipr_ensure_installed() {
    # Python3
    if ! command -v python3 &>/dev/null; then
        info "Ставлю Python3..."
        run_cmd apt-get update -qq >/dev/null 2>&1
        run_cmd apt-get install -y python3 >/dev/null 2>&1 || { err "Не удалось установить Python3."; return 1; }
    fi

    # yc CLI
    if ! command -v yc &>/dev/null && [[ ! -f "${HOME}/yandex-cloud/bin/yc" ]]; then
        info "Ставлю Yandex Cloud CLI..."
        curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh | bash -s -- -n >/dev/null 2>&1
        export PATH="${HOME}/yandex-cloud/bin:${PATH}"
        if ! command -v yc &>/dev/null && [[ ! -f "${HOME}/yandex-cloud/bin/yc" ]]; then
            err "Не удалось установить yc CLI."
            return 1
        fi
    fi

    # Скрипт roll_ip.py
    if [[ ! -f "$_IPR_SCRIPT_PATH" ]]; then
        info "Качаю скрипт IP-роллера..."
        mkdir -p "$_IPR_INSTALL_DIR"
        if curl -sL --fail -o "$_IPR_SCRIPT_PATH" "$_IPR_SCRIPT_URL"; then
            chmod +x "$_IPR_SCRIPT_PATH"
            ok "IP-роллер установлен."
        else
            err "Не удалось скачать скрипт роллера."
            return 1
        fi
    fi

    return 0
}

# --- Интерактивный запуск ---

_ipr_run_yandex() {
    clear
    menu_header "🎣 Ловля IP — Яндекс Облако"

    if ! _ipr_detect_yandex; then
        err "Братан, это не Яндекс сервер. Тут ловить нечего."
        return
    fi

    _ipr_ensure_installed || return

    # Получаем instance-id автоматически
    local instance_id
    instance_id=$(_ipr_get_instance_id)

    if [[ -z "$instance_id" ]]; then
        info "Не смог автоматом определить ID виртуалки."
        instance_id=$(ask_non_empty "Введи instance-id руками") || return
    else
        ok "Нашёл твою виртуалку: ${instance_id}"
        echo ""
    fi

    # Спрашиваем префикс
    local prefix
    prefix=$(safe_read "Фильтр по префиксу IP (рекомендуем 51.250, Enter — без фильтра)" "51.250") || return

    # Количество попыток
    local attempts
    attempts=$(safe_read "Максимум попыток" "500") || return

    echo ""
    info "Погнали крутить IP! Это может занять время..."
    print_separator
    echo ""

    # Собираем команду
    local cmd="python3 ${_IPR_SCRIPT_PATH} --instance-id ${instance_id} --attempts ${attempts}"
    if [[ -n "$prefix" ]]; then
        cmd+=" --prefix ${prefix}"
    fi

    # Запускаем
    eval "$cmd"
    local exit_code=$?

    echo ""
    if [[ $exit_code -eq 0 ]]; then
        ok "Красавчик! IP пойман."
        echo ""
        info "Хочешь зафиксировать этот IP? Выполни на своей машине:"
        printf_description "yc vpc address list"
        printf_description "yc vpc address update --reserved=true <address_id>"
    else
        warn "Не повезло, IP не нашёлся. Попробуй ещё раз или увеличь попытки."
    fi
}

# --- Меню ---

show_ip_roller_menu() {
    local is_yandex=0
    _ipr_detect_yandex && is_yandex=1

    enable_graceful_ctrlc
    while true; do
        clear
        menu_header "🎣 Ловля IP"
        printf_description "Прокрутка публичного IP до попадания в whitelist операторов."
        echo ""

        if [[ $is_yandex -eq 1 ]]; then
            printf_menu_option "1" "☁️  Яндекс Облако ${C_GREEN}(Обнаружено)${C_RESET}"
        else
            printf_menu_option "1" "☁️  Яндекс Облако ${C_RED}(Не подходит)${C_RESET}"
        fi
        echo ""
        printf_menu_option "b" "Назад"
        echo ""

        local choice
        choice=$(safe_read "Выбирай" "") || break

        case "$choice" in
            1)
                if [[ $is_yandex -eq 1 ]]; then
                    _ipr_run_yandex
                else
                    warn "Не-не-не, этот сервак не на Яндексе. Тут эта штука не прокатит."
                    sleep 2
                fi
                wait_for_enter
                ;;
            b|B) break ;;
            *) warn "Нет такого пункта." && sleep 1 ;;
        esac
    done
    disable_graceful_ctrlc
}
