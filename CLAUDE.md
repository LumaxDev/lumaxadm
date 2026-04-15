# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**LumaxADM** v3.0 — Bash TUI-фреймворк для управления Linux-серверами под VPN (Remnawave + Xray Core). Предоставляет интерактивные терминальные меню для управления флотом серверов (Skynet), настройки безопасности, шейпинга трафика, управления VPN-панелью Remnawave, дашборда метрик, Telegram-уведомлений и Docker.

- **Language:** Bash (`#!/bin/bash`), uses `set -uo pipefail`
- **Target OS:** Linux (Debian/Ubuntu via apt-get, Fedora/RHEL via dnf)
- **Entry point:** `lumaxadm.sh` — sources config and core modules, then routes to submodules via `run_module`

## Running

There is no build step. The project runs directly:
```bash
# On a target Linux server (installed via install.sh):
lumaxadm

# Local development (from repo root):
bash lumaxadm.sh
```

Modules are never executed directly — only through `run_module <path> <function>`. All modules expect `config/lumaxadm.conf` and `modules/core/common.sh` to be pre-loaded.

## Architecture

### Boot sequence
`lumaxadm.sh` → sources `config/lumaxadm.conf` → sources `modules/core/common.sh` → sources `modules/core/menu_generator.sh` (scans all .sh files for `@menu.manifest` blocks) → renders main menu loop.

### Menu manifest system
Menus are **declarative**. Each module declares its menu items in a comment block:
```bash
# @menu.manifest
# @item( PARENT | KEY | TITLE | FUNCTION | ORDER | GROUP | DESCRIPTION )
# @item( main | s | 🛡️ Security | show_security_menu | 50 | 50 | Server protection )
```
The generator (`modules/core/menu_generator.sh`) scans all modules at startup, builds menu trees in memory, and renders them via `render_menu_items "menu_id"` / `get_menu_action "menu_id" "$choice"`.

### Module loading
`run_module <module_path> <function> [args...]` — sources the module file and calls the function. All modules have a direct-execution guard: `[[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 1`.

### Plugin system
- **Dashboard widgets:** `plugins/dashboard_widgets/` — output `Label: Value` lines
- **Skynet commands:** `plugins/skynet_commands/<category>/` — must have `# TITLE: ...` header

## Code Style Rules (from docs/STYLE_GUIDE.md)

- Use `[[ ... ]]` not `[ ... ]`; use `$(...)` not backticks
- All variables inside functions must be `local`; use `${variable_name}` syntax
- Function naming: `snake_case`; private helpers prefixed with `_` (e.g., `_helper_function`)
- **Never use `echo`** for user messages — use helpers: `info`, `ok`, `warn`, `err`, `debug_log`
- **Never use raw ANSI codes** — use `${C_*}` color variables from `common.sh`, reset with `${C_RESET}`
- User input: `safe_read`, `ask_yes_no`, `ask_non_empty`, `ask_number_in_range`, `ask_password`, `wait_for_enter`
- System commands requiring sudo: always use `run_cmd`
- Config access: `get_config_var "KEY"` / `set_config_var "KEY" "VALUE"` — never edit lumaxadm.conf directly
- Dependencies: `ensure_dependencies "curl" "jq"`
- Logging: `log "message"` writes to `/var/log/lumaxadm.log`
- Menu loops: always wrap in `enable_graceful_ctrlc` / `disable_graceful_ctrlc`

## Key Directories

- `modules/core/` — common.sh (UI helpers, colors), menu_generator.sh, dependencies.sh, state_scanner.sh, self_update.sh
- `modules/security/` — firewall, fail2ban, kernel hardening, rkhunter, backup
- `modules/skynet/` — fleet DB, SSH keys, remote executor
- `modules/ui/` — dashboard, widget manager
- `modules/telegram/` — bot API, long-polling bot, inline keyboard builder
- `config/lumaxadm.conf` — all configuration constants and runtime settings
- `docs/` — STYLE_GUIDE.md, GUIDE_MODULES.md, GUIDE_SKYNET_WIDGETS.md

## Heredoc Generation

When generating child scripts (e.g., systemd units) via `cat << EOF`:
- `\$VAR` / `\$(cmd)` — evaluated at child script runtime
- `$VAR` — evaluated at generation time
- Never use `\\$` (double escaping)
- Don't use `local` in global scope of generated scripts
