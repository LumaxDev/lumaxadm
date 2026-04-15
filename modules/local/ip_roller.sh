#!/bin/bash
# ============================================================ #
# ==             МОДУЛЬ «ЛОВЛЯ IP»                           == #
# ============================================================ #
#
#  ( РОДИТЕЛЬ | КЛАВИША | НАЗВАНИЕ | ФУНКЦИЯ | ПОРЯДОК | ГРУППА | ОПИСАНИЕ )
# @menu.manifest
# @item( main | 4 | 🎣 Ловля IP | show_ip_roller_menu | 18 | 2 | Прокрутка IP до попадания в whitelist операторов. )
#
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1

readonly _IPR_SCRIPT_URL="https://raw.githubusercontent.com/princeofscale/yacloud-ip-roller/main/yacloud-ip-roller/roll_ip.py"
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

    # Проверяем что yc авторизован
    local yc_bin="${HOME}/yandex-cloud/bin/yc"
    command -v yc &>/dev/null && yc_bin="yc"

    # Проверяем что токен не просто есть, а реально рабочий
    local _yc_needs_setup=0
    if ! "$yc_bin" config list 2>/dev/null | grep -q "token"; then
        _yc_needs_setup=1
    elif ! "$yc_bin" resource-manager cloud list --format json 2>/dev/null | grep -q "id"; then
        warn "Токен Yandex Cloud невалидный или просрочен."
        if ask_yes_no "Перенастроить авторизацию?"; then
            _yc_needs_setup=1
        else
            err "Без рабочего токена ловля IP не заработает."
            return 1
        fi
    fi

    if [[ $_yc_needs_setup -eq 1 ]]; then
        warn "Yandex Cloud CLI нужно настроить."
        echo ""
        info "Нужно пройти авторизацию. Это делается один раз."
        echo ""
        printf_description "${C_WHITE}1.${C_RESET} Открой в браузере:"
        printf_description "${C_CYAN}https://oauth.yandex.ru/authorize?response_type=token&client_id=1a6990aa636648e9b2ef855fa7bec2fb${C_RESET}"
        printf_description "${C_WHITE}2.${C_RESET} Скопируй токен и вставь сюда:"
        echo ""

        local oauth_token
        oauth_token=$(safe_read "OAuth-токен" "") || return 1
        if [[ -z "$oauth_token" ]]; then
            err "Без токена никак, братан."
            return 1
        fi

        info "Настраиваю yc CLI..."
        "$yc_bin" config set token "$oauth_token" 2>/dev/null

        # Получаем список облаков и выбираем
        local cloud_list
        cloud_list=$("$yc_bin" resource-manager cloud list --format json 2>/dev/null)
        local cloud_id
        cloud_id=$(echo "$cloud_list" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')" 2>/dev/null)

        if [[ -n "$cloud_id" ]]; then
            "$yc_bin" config set cloud-id "$cloud_id" 2>/dev/null

            # Получаем список каталогов
            info "Ищу каталоги в облаке..."
            local folder_list
            folder_list=$("$yc_bin" resource-manager folder list --format json 2>/dev/null)
            local folder_count
            folder_count=$(echo "$folder_list" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)

            if [[ "$folder_count" == "1" ]]; then
                # Один каталог — берём автоматом
                local folder_id
                folder_id=$(echo "$folder_list" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])" 2>/dev/null)
                "$yc_bin" config set folder-id "$folder_id" 2>/dev/null
                ok "Каталог выбран автоматически."
            elif [[ "$folder_count" -gt 1 ]]; then
                # Несколько — показываем список
                echo ""
                "$yc_bin" resource-manager folder list 2>/dev/null
                echo ""
                local folder_id
                folder_id=$(safe_read "Вставь ID нужного каталога" "") || return 1
                if [[ -n "$folder_id" ]]; then
                    "$yc_bin" config set folder-id "$folder_id" 2>/dev/null
                    ok "Каталог установлен."
                fi
            fi
        fi

        # Финальная проверка
        if "$yc_bin" config list 2>/dev/null | grep -q "token"; then
            ok "Yandex Cloud CLI настроен!"
        else
            err "Что-то пошло не так. Попробуй вручную: ${yc_bin} init"
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

# --- Резервирование IP ---

_ipr_reserve_ip() {
    local target_ip="$1"
    local yc_bin="${HOME}/yandex-cloud/bin/yc"
    command -v yc &>/dev/null && yc_bin="yc"

    info "Ищу адрес ${target_ip} в Яндекс Облаке..."

    # Получаем список адресов и ищем нужный
    local address_id
    address_id=$("$yc_bin" vpc address list --format json 2>/dev/null \
        | python3 -c "
import sys, json
data = json.load(sys.stdin)
for addr in data:
    ip = addr.get('external_ipv4_address', {}).get('address', '')
    if ip == '${target_ip}':
        print(addr['id'])
        break
" 2>/dev/null)

    if [[ -z "$address_id" ]]; then
        warn "Не нашёл этот IP в списке адресов. Возможно он ещё не зарегистрирован как объект vpc."
        info "Попробуй вручную:"
        printf_description "yc vpc address list"
        printf_description "yc vpc address update --reserved=true <address_id>"
        return 1
    fi

    info "Нашёл: address_id=${address_id}. Резервирую..."

    if "$yc_bin" vpc address update --reserved=true "$address_id" >/dev/null 2>&1; then
        ok "IP ${target_ip} зафиксирован! Теперь он статический — никуда не денется."
    else
        err "Не удалось зарезервировать. Попробуй вручную:"
        printf_description "yc vpc address update --reserved=true ${address_id}"
        return 1
    fi
}

# --- Интерактивный запуск ---

_ipr_run_yandex() {
    clear
    menu_header "🎣 Ловля IP — Яндекс Облако"

    _ipr_ensure_installed || return

    # Предупреждение
    print_separator "─" 64
    printf "  ${C_YELLOW}⚠️  ВАЖНО:${C_RESET} Крути IP только с ${C_BOLD}другого сервера${C_RESET}!\n"
    printf "  Если крутить IP этого же сервера — потеряешь SSH.\n"
    printf "  Ловля работает через API Яндекса, не через SSH.\n"
    print_separator "─" 64
    echo ""

    # Показываем список VM если yc настроен
    local yc_bin="${HOME}/yandex-cloud/bin/yc"
    command -v yc &>/dev/null && yc_bin="yc"

    info "Ищу виртуалки в твоём облаке..."
    local vm_list
    vm_list=$("$yc_bin" compute instance list --format json 2>/dev/null)

    if [[ -n "$vm_list" ]] && echo "$vm_list" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d else 1)" 2>/dev/null; then
        echo ""

        echo "$vm_list" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if not data:
    sys.exit(0)
for i, vm in enumerate(data, 1):
    name = vm.get('name', '???')
    if len(name) > 20:
        name = name[:18] + '..'
    vid = vm.get('id', '???')
    status = vm.get('status', '???')
    ip = '—'
    for iface in vm.get('network_interfaces', []):
        nat = iface.get('primary_v4_address', {}).get('one_to_one_nat', {})
        if 'address' in nat:
            ip = nat['address']
            break
    print(f'  [{i}] {name}')
    print(f'      ID: {vid}')
    print(f'      IP: {ip}  |  {status}')
    print()
" 2>/dev/null

    fi

    # Спрашиваем ID
    info "Как найти ID виртуалки:"
    printf_description "Скопируй ID из таблицы выше"
    printf_description "Или: Яндекс Консоль → Compute Cloud → Виртуальные машины → ID"
    echo ""

    local instance_id
    instance_id=$(ask_non_empty "Instance ID виртуалки (чей IP крутим)") || return

    # Спрашиваем префикс
    local prefix
    prefix=$(safe_read "Префикс IP (например 51.250, 84.201 или пусто для любого)" "") || return

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

        # Определяем какой IP сейчас на виртуалке через yc API
        local caught_ip
        caught_ip=$("$yc_bin" compute instance get --id "$instance_id" --format json 2>/dev/null \
            | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['network_interfaces'][0]['primary_v4_address']['one_to_one_nat']['address'])" 2>/dev/null)

        echo ""
        if [[ -n "$caught_ip" ]]; then
            info "Пойманный IP: ${C_GREEN}${caught_ip}${C_RESET}"
            echo ""
            if ask_yes_no "Зафиксировать этот IP навсегда (сделать статическим)?" "y"; then
                _ipr_reserve_ip "$caught_ip"
            else
                info "Ок, IP остаётся эфемерным. При ребуте может смениться."
            fi
        else
            warn "Не смог определить текущий IP для резервирования."
            info "Можешь зафиксировать вручную:"
            printf_description "yc vpc address list"
            printf_description "yc vpc address update --reserved=true <address_id>"
        fi
    else
        warn "Не повезло, IP не нашёлся. Попробуй ещё раз или увеличь попытки."
    fi
}

# --- Меню ---

show_ip_roller_menu() {
    enable_graceful_ctrlc
    while true; do
        clear
        menu_header "🎣 Ловля IP"
        printf_description "Прокрутка публичного IP до попадания в whitelist операторов."
        echo ""

        printf_menu_option "1" "☁️  Яндекс Облако"
        echo ""
        printf_menu_option "b" "Назад"
        echo ""

        local choice
        choice=$(safe_read "Выбирай" "") || break

        case "$choice" in
            1)
                _ipr_run_yandex
                wait_for_enter
                ;;
            b|B) break ;;
            *) warn "Нет такого пункта." && sleep 1 ;;
        esac
    done
    disable_graceful_ctrlc
}
