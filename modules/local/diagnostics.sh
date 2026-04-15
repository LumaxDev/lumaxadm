#!/bin/bash
# ============================================================ #
# ==                МОДУЛЬ ДИАГНОСТИКИ                      == #
# ============================================================ #
#
# Отвечает за просмотр логов и управление Docker.
#  ( РОДИТЕЛЬ | КЛАВИША | НАЗВАНИЕ | ФУНКЦИЯ | ПОРЯДОК | ГРУППА | ОПИСАНИЕ )
# @menu.manifest
#
# @item( main | 5 | 📜 Диагностика и Логи ${C_YELLOW}(LumaxADM, Панель, Нода, Бот)${C_RESET} | show_diagnostics_menu | 30 | 2 | Быстрый просмотр логов основных компонентов системы. )
# @item( main | 6 | 🐳 Управление Docker ${C_YELLOW}(Мусорка, Инфо)${C_RESET} | show_docker_menu | 31 | 2 | Очистка, управление контейнерами, образами, сетями и томами. )
#
# @item( docker | 1 | 🧹 Очистка мусора | _show_docker_cleanup_menu | 10 | 1 | Освобождает место, удаляя неиспользуемые образы, кэш и тома. )
# @item( docker | 2 | 📦 Контейнеры | _show_docker_containers_menu | 20 | 1 | Просмотр логов, старт/стоп, удаление и вход в контейнеры. )
# @item( docker | 3 | 🌐 Сети Docker | _show_docker_networks_menu | 30 | 1 | Просмотр и инспектирование сетей. )
# @item( docker | 4 | 💽 Тома Docker | _show_docker_volumes_menu | 40 | 1 | Просмотр, инспектирование и удаление томов. )
# @item( docker | 5 | 🖼️ Образы Docker | _show_docker_images_menu | 50 | 1 | Просмотр, удаление и запуск контейнеров из образов. )
#
# @item( docker_cleanup | 1 | 📊 Показать самые большие образы | _docker_action_list_large_images | 10 | 1 | Список образов, отсортированных по размеру. )
# @item( docker_cleanup | 2 | 🧹 Простая очистка | _docker_action_prune_system | 20 | 1 | Удаляет 'висячие' образы и кэш сборки. )
# @item( docker_cleanup | 3 | 💥 Полная очистка образов | _docker_action_prune_images | 30 | 1 | Удаляет ВСЕ неиспользуемые образы. )
# @item( docker_cleanup | 4 | 🗑️ Очистка томов (ОСТОРОЖНО!) | _docker_action_prune_volumes | 40 | 1 | Удаляет ВСЕ тома, не привязанные к контейнерам. )
# @item( docker_cleanup | 5 | 📈 Показать итоговое использование диска | _docker_action_system_df | 50 | 1 | Выполняет 'docker system df'. )
#
# @item( docker_containers | 1 | 📦 Список всех контейнеров | _docker_action_list_containers | 10 | 1 | Показывает все контейнеры (запущенные и остановленные). )
# @item( docker_containers | 2 | 📜 Посмотреть логи | _docker_action_view_logs | 20 | 1 | Показывает логи выбранного контейнера в реальном времени. )
# @item( docker_containers | 3 | 🕹️ Управление (Старт/Стоп/Рестарт) | _docker_action_manage_container | 30 | 1 | Запускает, останавливает или перезапускает контейнер. )
# @item( docker_containers | 4 | 🗑️ Удалить контейнер | _docker_action_remove_container | 40 | 1 | Останавливает и полностью удаляет выбранный контейнер. )
# @item( docker_containers | 5 | 🔍 Инспектировать контейнер | _docker_action_inspect_container | 50 | 1 | Выводит подробную информацию о контейнере (JSON). )
# @item( docker_containers | 6 | 📈 Статистика по ресурсам | _docker_action_container_stats | 60 | 1 | Показывает текущее потребление ресурсов контейнером. )
# @item( docker_containers | 7 | 🐚 Войти в контейнер (exec) | _docker_action_exec_container | 70 | 1 | Открывает интерактивную оболочку внутри контейнера. )
#
# @item( docker_networks | 1 | 🌐 Список сетей | _docker_action_list_networks | 10 | 1 | Показывает все сети, созданные Docker. )
# @item( docker_networks | 2 | 🔍 Инспектировать сеть | _docker_action_inspect_network | 20 | 1 | Выводит подробную информацию о выбранной сети. )
#
# @item( docker_volumes | 1 | 📦 Список томов | _docker_action_list_volumes | 10 | 1 | Показывает все тома, созданные Docker. )
# @item( docker_volumes | 2 | 🔍 Инспектировать том | _docker_action_inspect_volume | 20 | 1 | Выводит подробную информацию о выбранном томе. )
# @item( docker_volumes | 3 | 🗑️ Удалить том | _docker_action_remove_volume | 30 | 1 | Удаляет выбранный том (требует подтверждения). )
#
# @item( docker_images | 1 | 🖼️ Список образов | _docker_action_list_all_images | 10 | 1 | Показывает все образы, созданные Docker. )
# @item( docker_images | 2 | 🔍 Инспектировать образ | _docker_action_inspect_image | 20 | 1 | Выводит подробную информацию о выбранном образе. )
# @item( docker_images | 3 | 🗑️ Удалить образ | _docker_action_remove_image | 30 | 1 | Удаляет выбранный образ (требует подтверждения). )
# @item( docker_images | 4 | ▶️ Запустить временный контейнер | _docker_action_run_temp_container | 40 | 1 | Запускает временный контейнер из выбранного образа. )
#

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1 # Защита от прямого запуска

# ============================================================ #
#                  ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ                     #
# ============================================================ #

_docker_safe() { if command -v timeout &>/dev/null; then timeout 10 docker "$@"; else docker "$@"; fi; }
_docker_select_container() { local list; list=$(_docker_safe ps -a --format '{{.ID}}|{{.Names}}|{{.Status}}') || return 1; if [[ -z "$list" ]]; then printf_warning "Контейнеров не найдено."; return 1; fi; >&2 echo ""; >&2 print_separator "-" 40; local i=1; local ids=(); local names=(); while IFS='|' read -r id name status; do >&2 printf "   [%d] %s  %s  (%s)\n" "$i" "$id" "$name" "$status"; ids[$i]="$id"; names[$i]="$name"; ((i++)); done <<< "$list"; >&2 print_separator "-" 40; local choice; choice=$(ask_number_in_range "Выбери номер контейнера" 1 "$((i-1))") || return 1; if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ -z "${names[$choice]:-}" ]; then printf_error "Нет такого номера."; return 1; fi; echo "${names[$choice]}"; return 0; }
_docker_select_network() { local list; list=$(_docker_safe network ls --format '{{.Name}}|{{.Driver}}|{{.Scope}}') || return 1; if [[ -z "$list" ]]; then printf_warning "Сетей не найдено."; return 1; fi; >&2 echo ""; >&2 printf_info "Список сетей:"; >&2 print_separator "-" 40; local i=1; local names=(); while IFS='|' read -r name driver scope; do >&2 printf "   [%d] %s (%s, %s)\n" "$i" "$name" "$driver" "$scope"; names[$i]="$name"; ((i++)); done <<< "$list"; >&2 print_separator "-" 40; local choice; choice=$(ask_number_in_range "Выбери номер сети" 1 "$((i-1))") || return 1; if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ -z "${names[$choice]:-}" ]; then printf_error "Нет такого номера."; return 1; fi; echo "${names[$choice]}"; return 0; }
_docker_select_volume() { local list; list=$(_docker_safe volume ls --format '{{.Name}}|{{.Driver}}') || return 1; if [[ -z "$list" ]]; then printf_warning "Томов не найдено."; return 1; fi; >&2 echo ""; >&2 printf_info "Список томов:"; >&2 print_separator "-" 40; local i=1; local names=(); while IFS='|' read -r name driver; do >&2 printf "   [%d] %s (%s)\n" "$i" "$name" "$driver"; names[$i]="$name"; ((i++)); done <<< "$list"; >&2 print_separator "-" 40; local choice; choice=$(ask_number_in_range "Выбери номер тома" 1 "$((i-1))") || return 1; if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ -z "${names[$choice]:-}" ]; then printf_error "Нет такого номера."; return 1; fi; echo "${names[$choice]}"; return 0; }
_docker_select_image() { local list; list=$(_docker_safe images --format '{{.Repository}}:{{.Tag}}|{{.ID}}|{{.Size}}') || return 1; if [[ -z "$list" ]]; then printf_warning "Образов не найдено."; return 1; fi; >&2 echo ""; >&2 printf_info "Список образов (REPO:TAG / ID / SIZE):"; >&2 print_separator "-" 40; local i=1; local names=(); while IFS='|' read -r name id size; do >&2 printf "   [%d] %s  (%s, %s)\n" "$i" "$name" "$id" "$size"; names[$i]="$name"; ((i++)); done <<< "$list"; >&2 print_separator "-" 40; local choice; choice=$(ask_number_in_range "Выбери номер образа" 1 "$((i-1))") || return 1; if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ -z "${names[$choice]:-}" ]; then printf_error "Нет такого номера."; return 1; fi; echo "${names[$choice]}"; return 0; }

# --- Функции-действия ---
_docker_action_list_large_images() { echo; _docker_safe images --format "{{.Repository}}:{{.Tag}}\t{{.Size}}" | sort -rh | head; wait_for_enter; }
_docker_action_prune_system() { _docker_safe system prune -f; printf_ok "Простая очистка завершена."; wait_for_enter; }
_docker_action_prune_images() { if ask_yes_no "Удалить ВСЕ неиспользуемые образы? (y/n): " "n"; then _docker_safe image prune -a -f; printf_ok "Полная очистка образов завершена."; fi; wait_for_enter; }
_docker_action_prune_volumes() { printf_critical_warning "ОСТОРОЖНО!"; if ask_yes_no "Удалить ВСЕ тома, не привязанные к контейнерам? (y/n): " "n"; then _docker_safe volume prune -f; printf_ok "Очистка томов завершена."; fi; wait_for_enter; }
_docker_action_system_df() { echo; _docker_safe system df; wait_for_enter; }
_docker_action_list_containers() { echo; _docker_safe ps -a; wait_for_enter; }
_docker_action_view_logs() { local name; name=$(_docker_select_container) || { wait_for_enter; return; }; printf_info "--- ЛОГИ $name (CTRL+C, чтобы выйти) ---"; docker logs -f "$name"; }
_docker_action_manage_container() { local name; name=$(_docker_select_container) || { wait_for_enter; return; }; printf_info "   1) Старт  2) Стоп  3) Рестарт"; local act; act=$(safe_read "Действие: " "1"); case "$act" in 1) _docker_safe start "$name";; 2) _docker_safe stop "$name";; 3) _docker_safe restart "$name";; *) printf_error "Нет такого действия.";; esac; wait_for_enter; }
_docker_action_remove_container() { local name; name=$(_docker_select_container) || { wait_for_enter; return; }; if ask_yes_no "Точно снести '$name'? (y/n): " "n"; then _docker_safe stop "$name" &>/dev/null; _docker_safe rm "$name"; fi; wait_for_enter; }
_docker_action_inspect_container() { local name; name=$(_docker_select_container) || { wait_for_enter; return; }; printf_info "--- docker inspect $name ---"; _docker_safe inspect "$name"; wait_for_enter; }
_docker_action_container_stats() { local name; name=$(_docker_select_container) || { wait_for_enter; return; }; printf_info "--- docker stats (снимок) для $name ---"; _docker_safe stats --no-stream "$name"; wait_for_enter; }
_docker_action_exec_container() { local name; name=$(_docker_select_container) || { wait_for_enter; return; }; printf_info "Входим в контейнер '$name' (bash/sh). Выйти: exit"; docker exec -it "$name" bash 2>/dev/null || docker exec -it "$name" sh; }
_docker_action_list_networks() { echo; _docker_safe network ls; wait_for_enter; }
_docker_action_inspect_network() { local net; net=$(_docker_select_network) || { wait_for_enter; return; }; _docker_safe network inspect "$net"; wait_for_enter; }
_docker_action_list_volumes() { echo; _docker_safe volume ls; wait_for_enter; }
_docker_action_inspect_volume() { local vol; vol=$(_docker_select_volume) || { wait_for_enter; return; }; _docker_safe volume inspect "$vol"; wait_for_enter; }
_docker_action_remove_volume() { local vol; vol=$(_docker_select_volume) || { wait_for_enter; return; }; if ask_yes_no "Точно снести том '$vol'? (y/n): " "n"; then _docker_safe volume rm "$vol"; fi; wait_for_enter; }
_docker_action_list_all_images() { echo; _docker_safe images; wait_for_enter; }
_docker_action_inspect_image() { local img; img=$(_docker_select_image) || { wait_for_enter; return; }; echo "--- docker image inspect $img ---"; _docker_safe image inspect "$img"; wait_for_enter; }
_docker_action_remove_image() { local img; img=$(_docker_select_image) || { wait_for_enter; return; }; if ask_yes_no "Точно снести образ '$img'? (y/n): " "n"; then _docker_safe rmi "$img"; fi; wait_for_enter; }
_docker_action_run_temp_container() { local img; img=$(_docker_select_image) || { wait_for_enter; return; }; echo "Введи команду внутри контейнера (по умолчанию /bin/bash):"; local cmd; cmd=$(safe_read "Команда: " "/bin/bash"); docker run -it --rm "$img" "$cmd"; }

# ============================================================ #
#                         ФУНКЦИИ МЕНЮ                         #
# ============================================================ #

# --- Универсальный шаблон для всех подменю этого модуля ---
_show_diagnostics_submenu() {
    local menu_id="$1"; local title="$2"; local description="$3"
    enable_graceful_ctrlc
    while true; do
        clear; menu_header "$title"; [[ -n "$description" ]] && printf_description "$description"
        echo ""; render_menu_items "$menu_id"; echo ""; printf_menu_option "b" "🔙 Назад"; print_separator "-" 60
        local choice; choice=$(safe_read "Твой выбор: " "") || break
        if [[ "$choice" == "b" || "$choice" == "B" ]]; then break; fi
        local action; action=$(get_menu_action "$menu_id" "$choice")
        if [[ -n "$action" ]]; then eval "$action"; else warn "Неверный выбор"; fi
    done
    disable_graceful_ctrlc
}

# --- Реализации меню через шаблон ---
_show_docker_cleanup_menu() { _show_diagnostics_submenu "docker_cleanup" "🐳 DOCKER: ОЧИСТКА ДИСКА" "Освобождение места, занятого Docker."; }
_show_docker_containers_menu() { _show_diagnostics_submenu "docker_containers" "🐳 DOCKER: УПРАВЛЕНИЕ КОНТЕЙНЕРАМИ" ""; }
_show_docker_networks_menu() { _show_diagnostics_submenu "docker_networks" "🐳 DOCKER: СЕТИ" ""; }
_show_docker_volumes_menu() { _show_diagnostics_submenu "docker_volumes" "🐳 DOCKER: ТОМА" ""; }
_show_docker_images_menu() { _show_diagnostics_submenu "docker_images" "🐳 DOCKER: ОБРАЗЫ" ""; }
show_docker_menu() { _show_diagnostics_submenu "docker" "🐳 УПРАВЛЕНИЕ DOCKER" "Просмотр состояния и управление всеми компонентами Docker."; }

# --- Меню логов (оставлено с `case` из-за условной логики) ---
show_diagnostics_menu() {
    enable_graceful_ctrlc
    while true; do
        run_module core/state_scanner scan_remnawave_state
        clear
        menu_header "📜 Диагностика и Логи"
        printf_description "Быстрый просмотр логов основных компонентов системы (выйти: CTRL+C)."
        echo ""; printf_menu_option "1" "📒 Журнал «LumaxADM»"
        if [[ "$SERVER_TYPE" == *"Панель"* ]]; then printf_menu_option "2" "📊 Логи Панели"; fi
        if [[ "$SERVER_TYPE" == *"Нода"* ]]; then printf_menu_option "3" "📡 Логи Ноды"; fi
        if [ "${BOT_DETECTED:-0}" -eq 1 ]; then printf_menu_option "4" "🤖 Логи Бота"; fi
        echo ""
        printf_menu_option "5" "🔬 Рентген Xray (подключения, DDoS-детект)"
        echo ""; printf_menu_option "b" "🔙 Назад"; print_separator "-" 60
        local choice; choice=$(safe_read "Какой лог курим?" "") || break
        case "$choice" in
            1) view_logs_realtime "$LOGFILE" "LumaxADM" ;;
            2) if [[ "$SERVER_TYPE" == *"Панель"* ]]; then view_docker_logs "$PANEL_NODE_PATH" "Панели"; else printf_error "Панели нет."; fi;;
            3) if [[ "$SERVER_TYPE" == *"Нода"* ]]; then view_docker_logs "$PANEL_NODE_PATH" "Ноды"; else printf_error "Ноды нет."; fi;;
            4) if [ "${BOT_DETECTED:-0}" -eq 1 ]; then view_docker_logs "${BOT_PATH}/docker-compose.yml" "Бота"; else printf_error "Бота нет."; fi;;
            5) run_module local/xray_scanner show_xray_scanner_menu ;;
            [bB]) break ;;
        esac
    done
    disable_graceful_ctrlc
}
