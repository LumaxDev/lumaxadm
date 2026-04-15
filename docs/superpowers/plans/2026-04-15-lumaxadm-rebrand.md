# LumaxADM Rebrand & Bugfix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Полный ребрендинг «Решала» → «LumaxADM», удаление модуля Bedalaga, фикс бага смены SSH-порта.

**Architecture:** Bash TUI framework. Точка входа `reshala.sh` → переименовывается в `lumaxadm.sh`. Конфиг `config/reshala.conf` → `config/lumaxadm.conf`. Все пути, переменные, имена сервисов, jail-ы fail2ban, SSH-ключи, временные файлы меняют префикс `reshala` → `lumaxadm`.

**Tech Stack:** Bash, UFW, sshd, systemd, fail2ban, eBPF

---

### Task 1: Удаление модуля Bedalaga бот

**Files:**
- Delete: `modules/bot_bedolaga/menu.sh`
- Delete: directory `modules/bot_bedolaga/`

- [ ] **Step 1: Удалить директорию modules/bot_bedolaga/**

```bash
rm -rf modules/bot_bedolaga
```

Проверка: `ls modules/bot_bedolaga` должен вернуть ошибку "No such file or directory".

- [ ] **Step 2: Проверить отсутствие ссылок на bedalaga в остальном коде**

```bash
grep -ri "bedalaga\|bedolaga" --include="*.sh" --include="*.conf" modules/ config/ reshala.sh plugins/
```

Ожидаемый результат: **пусто** (ни одного совпадения, т.к. манифест был только в удалённом файле).

---

### Task 2: Ребрендинг — переименование файлов

**Files:**
- Rename: `reshala.sh` → `lumaxadm.sh`
- Rename: `config/reshala.conf` → `config/lumaxadm.conf`

- [ ] **Step 1: Переименовать главный файл**

```bash
mv reshala.sh lumaxadm.sh
```

- [ ] **Step 2: Переименовать конфиг**

```bash
mv config/reshala.conf config/lumaxadm.conf
```

---

### Task 3: Ребрендинг — обновление config/lumaxadm.conf

**Files:**
- Modify: `config/lumaxadm.conf`

- [ ] **Step 1: Обновить заголовок и комментарии**

Заменить:
```
# ==           КОНФИГУРАЦИЯ "РЕШАЛА-ФРЕЙМВОРК"             == #
```
На:
```
# ==           КОНФИГУРАЦИЯ "LUMAXADM"                      == #
```

Заменить:
```
# "Решалу" под себя, не трогая основной код.
```
На:
```
# LumaxADM под себя, не трогая основной код.
```

- [ ] **Step 2: Обновить пути и имена**

Заменить все вхождения:
- `reshala.log` → `lumaxadm.log`
- `/usr/local/bin/reshala` → `/usr/local/bin/lumaxadm`
- `.reshala_fleet` → `.lumaxadm_fleet`
- `id_ed25519_reshala_master` → `id_ed25519_lumaxadm_master`
- `id_ed25519_reshala_node_` → `id_ed25519_lumaxadm_node_`

- [ ] **Step 3: Обновить URL-ы репозитория**

Заменить:
- `REPO_NAME="Reshala-Remnawave-Bedolaga"` → `REPO_NAME="LumaxADM"`
- В `SCRIPT_URL_RAW` заменить `reshala.sh` → `lumaxadm.sh`

---

### Task 4: Ребрендинг — обновление lumaxadm.sh (бывший reshala.sh)

**Files:**
- Modify: `lumaxadm.sh`

- [ ] **Step 1: Обновить заголовок**

```
# ==      ИНСТРУМЕНТ «РЕШАЛА» v3.0 - РЕФАКТОРИНГ МЕНЮ        == #
```
→
```
# ==            ИНСТРУМЕНТ «LumaxADM» v3.0                    == #
```

- [ ] **Step 2: Обновить манифест меню**

```
# @item( main | d | 🗑️  Снести Решалу | _lumaxadm_uninstall_wrapper | 90 | 90 | Удаляет все файлы и конфигурацию LumaxADM. )
```

- [ ] **Step 3: Обновить путь к конфигу**

Заменить все `reshala.conf` → `lumaxadm.conf` (строки 32-35).

- [ ] **Step 4: Переименовать функцию**

`_reshala_uninstall_wrapper` → `_lumaxadm_uninstall_wrapper`

- [ ] **Step 5: Обновить show_support_page**

- Заменить логотип ASCII-art «РЕШАЛА» на «LUMAXADM»
- `LINK_GROUP_URL` — обновить URL ТГ если есть новый
- `LINK_SITE_URL` — обновить URL репозитория
- Заменить текст "Группа ТГ Решалы" → "Группа ТГ LumaxADM"
- Заменить текст "Сайт Решалы" → "Сайт LumaxADM"

- [ ] **Step 6: Обновить тексты главного меню**

- `"Для выхода из Решалы используй [q]."` → `"Для выхода из LumaxADM используй [q]."`
- `"ОБНОВИТЬ РЕШАЛУ"` → `"ОБНОВИТЬ LUMAXADM"`
- `"Выйти из решалы"` → `"Выйти из LumaxADM"`
- `"Запуск фреймворка Решала"` → `"Запуск фреймворка LumaxADM"`

---

### Task 5: Ребрендинг — обновление modules/core/common.sh

**Files:**
- Modify: `modules/core/common.sh:431,441`

- [ ] **Step 1: Обновить пути к конфигу**

Строки 431 и 441 — заменить `reshala.conf` → `lumaxadm.conf`.

---

### Task 6: Ребрендинг — обновление modules/core/self_update.sh

**Files:**
- Modify: `modules/core/self_update.sh`

- [ ] **Step 1: Обновить все упоминания**

Заменить:
- `"Решалы"` / `"Решала"` / `"Решалу"` → `"LumaxADM"`
- `/tmp/reshala_archive` → `/tmp/lumaxadm_archive`
- `/tmp/reshala_extracted` → `/tmp/lumaxadm_extracted`
- `/opt/reshala` → `/opt/lumaxadm`
- `reshala.sh` → `lumaxadm.sh`
- `alias reshala=` → `alias lumaxadm=`
- `RESHALA_NO_AUTOSTART` → `LUMAXADM_NO_AUTOSTART`
- команда `reshala` → `lumaxadm` (строка 68)
- wrapper путь `/usr/local/bin/reshala` → `/usr/local/bin/lumaxadm`
- Текст в wrapper "Лаунчер Решалы" → "Лаунчер LumaxADM"
- `TARGET="/opt/reshala/reshala.sh"` → `TARGET="/opt/lumaxadm/lumaxadm.sh"`

---

### Task 7: Ребрендинг — обновление modules/core/menu_generator.sh

**Files:**
- Modify: `modules/core/menu_generator.sh:92,115,117`

- [ ] **Step 1: Обновить ссылки на главный файл**

- Строка 92: комментарий `reshala.sh` → `lumaxadm.sh`
- Строка 115: комментарий `reshala.sh` → `lumaxadm.sh`
- Строка 117: `"${SCRIPT_DIR}/reshala.sh"` → `"${SCRIPT_DIR}/lumaxadm.sh"`

---

### Task 8: Ребрендинг — обновление modules/skynet/

**Files:**
- Modify: `modules/skynet/executor.sh`
- Modify: `modules/skynet/keys.sh`
- Modify: `modules/skynet/menu.sh`

- [ ] **Step 1: executor.sh — обновить имена временных файлов**

- `/tmp/reshala_plugin.sh` → `/tmp/lumaxadm_plugin.sh` (строки 18, 19, 28, 30)
- `/tmp/reshala_plugin_` → `/tmp/lumaxadm_plugin_` (строка 42)

- [ ] **Step 2: keys.sh — обновить префиксы ключей**

- `reshala_imported_` → `lumaxadm_imported_` (строки 140, 153, 154, 261, 265, 312, 319, 322)
- `reshala_pasted_key_` → `lumaxadm_pasted_key_` (menu.sh строка 99)
- Текстовые строки "Reshala" → "LumaxADM" (строки 217, 265, 355, 363)

- [ ] **Step 3: menu.sh — обновить удалённые команды**

- `RESHALA_NO_AUTOSTART=1` → `LUMAXADM_NO_AUTOSTART=1` (строка 325)
- `/opt/reshala/reshala.sh` → `/opt/lumaxadm/lumaxadm.sh` (строка 336)

---

### Task 9: Ребрендинг — обновление modules/security/

**Files:**
- Modify: `modules/security/backup.sh`
- Modify: `modules/security/fail2ban.sh`
- Modify: `modules/security/kernel.sh`
- Modify: `modules/security/rkhunter.sh`
- Modify: `modules/security/status.sh`

- [ ] **Step 1: backup.sh — обновить пути и имена**

- `99-reshala-hardening.conf` → `99-lumaxadm-hardening.conf`
- `/etc/reshala/` → `/etc/lumaxadm/`
- `reshala-security-backup-` → `lumaxadm-security-backup-`
- `reshala.conf` → `lumaxadm.conf`

- [ ] **Step 2: fail2ban.sh — обновить jail-имена и пути**

- `/etc/reshala/` → `/etc/lumaxadm/`
- `portscan-reshala` → `portscan-lumaxadm`
- `nginx-auth-reshala` → `nginx-auth-lumaxadm`
- `nginx-bots-reshala` → `nginx-bots-lumaxadm`

- [ ] **Step 3: kernel.sh — обновить имя конфига**

- `99-reshala-hardening.conf` → `99-lumaxadm-hardening.conf`
- `"Generated by Reshala"` → `"Generated by LumaxADM"`

- [ ] **Step 4: rkhunter.sh — обновить имена**

- `reshala-rkhunter-scan` → `lumaxadm-rkhunter-scan`
- `"Reshala Security Module"` → `"LumaxADM Security Module"`
- `reshala_rkhunter_last.log` → `lumaxadm_rkhunter_last.log`

- [ ] **Step 5: status.sh — обновить проверки путей**

- `99-reshala-hardening.conf` → `99-lumaxadm-hardening.conf`
- `reshala-rkhunter-scan` → `lumaxadm-rkhunter-scan`

---

### Task 10: Ребрендинг — обновление modules/local/

**Files:**
- Modify: `modules/local/traffic_limiter.sh`
- Modify: `modules/local/local_care.sh`
- Modify: `modules/local/diagnostics.sh`

- [ ] **Step 1: traffic_limiter.sh — обновить пути и имена сервисов**

- `/etc/reshala/traffic_limiter` → `/etc/lumaxadm/traffic_limiter`
- `reshala_ctrl.py` → `lumaxadm_ctrl.py`
- `reshala-traffic-limiter.service` → `lumaxadm-traffic-limiter.service`
- `/usr/local/bin/reshala-traffic-limiter-apply.sh` → `/usr/local/bin/lumaxadm-traffic-limiter-apply.sh`
- `/sys/fs/bpf/reshala` → `/sys/fs/bpf/lumaxadm`
- `"Reshala eBPF"` → `"LumaxADM eBPF"`

- [ ] **Step 2: local_care.sh — обновить конфиг**

- `99-reshala-boost.conf` → `99-lumaxadm-boost.conf`
- `КОНФИГ «ФОРСАЖ» ОТ РЕШАЛЫ` → `КОНФИГ «ФОРСАЖ» ОТ LUMAXADM`
- `/var/backups/reshala_apt_` → `/var/backups/lumaxadm_apt_`

- [ ] **Step 3: diagnostics.sh — обновить тексты**

- `Решала, Панель, Нода, Бот` → `LumaxADM, Панель, Нода, Бот`
- `Журнал «Решалы»` → `Журнал «LumaxADM»`
- `"Решалы"` → `"LumaxADM"`

---

### Task 11: Ребрендинг — обновление modules/ui/, modules/telegram/

**Files:**
- Modify: `modules/ui/dashboard.sh`
- Modify: `modules/ui/widget_manager.sh`
- Modify: `modules/telegram/menu.sh`
- Modify: `modules/telegram/bot.sh`

- [ ] **Step 1: dashboard.sh**

- `/etc/reshala/traffic_limiter` → `/etc/lumaxadm/traffic_limiter`
- `/tmp/reshala_widgets_cache` → `/tmp/lumaxadm_widgets_cache`
- `"Агент Решалы"` → `"Агент LumaxADM"`
- `"ИНСТРУМЕНТ «РЕШАЛА»"` → `"ИНСТРУМЕНТ «LumaxADM»"`

- [ ] **Step 2: widget_manager.sh**

- `/tmp/reshala_widgets_cache` → `/tmp/lumaxadm_widgets_cache`

- [ ] **Step 3: telegram/menu.sh**

- `reshala.conf` → `lumaxadm.conf`
- `"Reshala"` → `"LumaxADM"`
- `reshala-notify-login.sh` → `lumaxadm-notify-login.sh`

- [ ] **Step 4: telegram/bot.sh**

- `/tmp/reshala_bot.pid` → `/tmp/lumaxadm_bot.pid`
- `"Reshala"` → `"LumaxADM"`

---

### Task 12: Ребрендинг — обновление plugins/

**Files:**
- Modify: `plugins/skynet_commands/security/00_get_security_status.sh`
- Modify: `plugins/skynet_commands/security/01_harden_ssh.sh`
- Modify: `plugins/skynet_commands/security/05_apply_kernel.sh`
- Modify: `plugins/skynet_commands/security/06_setup_ssh_login_notify.sh`
- Modify: `plugins/skynet_commands/remnawave/01_install_node.sh`
- Modify: `plugins/dashboard_widgets/01_crypto_price.sh`

- [ ] **Step 1: Плагины security**

- `99-reshala-hardening.conf` → `99-lumaxadm-hardening.conf`
- `.bak_reshala_` → `.bak_lumaxadm_`
- `"Reshala Security Module"` → `"LumaxADM Security Module"`
- `reshala-notify-login.sh` → `lumaxadm-notify-login.sh`
- `"Reshala: SSH Login Notifier"` → `"LumaxADM: SSH Login Notifier"`

- [ ] **Step 2: Плагин remnawave**

- `'reshala remnanode acme http-01'` → `'lumaxadm remnanode acme http-01'`
- `Решалы/Skynet` → `LumaxADM/Skynet`

- [ ] **Step 3: Виджет crypto_price**

- `"Решалы"` → `"LumaxADM"`

---

### Task 13: Ребрендинг — обновление install.sh

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: Обновить все упоминания**

- `«Решала»` → `«LumaxADM»`
- `REPO_NAME="Reshala-Remnawave-Bedolaga"` → `REPO_NAME="LumaxADM"`
- `/tmp/reshala_bootstrap` → `/tmp/lumaxadm_bootstrap`
- `reshala.tar.gz` → `lumaxadm.tar.gz`
- `reshala.sh` → `lumaxadm.sh`
- `"Решалы"` → `"LumaxADM"`

---

### Task 14: Ребрендинг — обновление CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Полностью обновить CLAUDE.md**

Переписать файл с учётом нового имени LumaxADM, обновлённых путей файлов (`lumaxadm.sh`, `config/lumaxadm.conf`).

---

### Task 15: Фикс бага смены SSH-порта

**Files:**
- Modify: `modules/security/firewall.sh` (функция `_firewall_reconfigure_wizard`, строки ~216-286)

- [ ] **Step 1: Добавить логику реальной смены порта SSH**

После строки 219 (`ssh_port=$(safe_read "SSH порт" "$ssh_port") || return`), перед применением правил UFW, добавить блок:

```bash
    # --- Реальная смена порта SSH в sshd_config ---
    local current_ssh_port
    current_ssh_port=$(grep "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    current_ssh_port=${current_ssh_port:-22}

    if [[ "$ssh_port" != "$current_ssh_port" ]]; then
        info "Меняю порт SSH с ${current_ssh_port} на ${ssh_port}..."
        
        # Бэкап sshd_config
        local sshd_backup="/etc/ssh/sshd_config.bak_lumaxadm_$(date +%s)"
        run_cmd cp /etc/ssh/sshd_config "$sshd_backup"
        
        # Меняем порт в конфиге
        run_cmd sed -i -e "s/^#*Port .*/Port $ssh_port/" /etc/ssh/sshd_config
        if ! grep -q "^Port " /etc/ssh/sshd_config; then
            echo "Port $ssh_port" | run_cmd tee -a /etc/ssh/sshd_config >/dev/null
        fi
        
        # Перезапускаем SSH
        if ! (run_cmd systemctl restart sshd 2>/dev/null || run_cmd systemctl restart ssh 2>/dev/null); then
            warn "Не удалось перезапустить SSH! Откатываю изменения..."
            run_cmd mv "$sshd_backup" /etc/ssh/sshd_config
            run_cmd systemctl restart sshd 2>/dev/null || run_cmd systemctl restart ssh 2>/dev/null || true
            err "Откат выполнен. Порт SSH не изменён."
            return 1
        fi
        
        sleep 2
        
        # Проверяем что SSH слушает новый порт
        if ! ss -tlnp | grep -q ":${ssh_port}"; then
            warn "SSH не слушает новый порт! Откатываю..."
            run_cmd mv "$sshd_backup" /etc/ssh/sshd_config
            run_cmd systemctl restart sshd 2>/dev/null || run_cmd systemctl restart ssh 2>/dev/null || true
            err "Откат выполнен. Порт SSH не изменён."
            return 1
        fi
        
        ok "SSH теперь слушает порт ${ssh_port}."
        
        # Сохраняем в конфиг
        set_config_var "SSH_PORT" "$ssh_port"
    fi
```

- [ ] **Step 2: Убедиться что порт читается из sshd_config как fallback**

Заменить строки 216-218:
```bash
    local ssh_port
    ssh_port=$(get_config_var "SSH_PORT")
    ssh_port=${ssh_port:-22}
```
На:
```bash
    local ssh_port
    ssh_port=$(grep "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    ssh_port=${ssh_port:-22}
```

Это гарантирует что текущий реальный порт SSH определяется из `sshd_config`, а не из конфига LumaxADM.

---

### Task 16: Финальная проверка — grep на остатки старого бренда

- [ ] **Step 1: Поиск остатков**

```bash
grep -ri "решал\|reshala\|RESHALA" --include="*.sh" --include="*.conf" .
```

Ожидаемый результат: **ни одного совпадения** в .sh и .conf файлах (в .md файлах документации могут остаться упоминания — README.md, WARP.md и пр., это нормально, их обновит пользователь при переносе репозитория).

- [ ] **Step 2: Проверка что lumaxadm.sh парсится без ошибок**

```bash
bash -n lumaxadm.sh
```

Ожидаемый результат: **без ошибок** (код 0).
