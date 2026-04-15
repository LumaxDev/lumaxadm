#!/bin/bash
# TITLE: Обновления и ядро
# Виджет для дашборда LumaxADM: показывает давность обновления и статус ядра.
#
# КАК НАСТРОИТЬ ПОД СЕБЯ:
#   - WARN_DAYS=7 — через сколько дней начинать напоминать об обновлении.
#   - Можно поменять на 14, 30 и т.д.

WARN_DAYS=7

# --- Давность последнего обновления ---
last_update=0
if [ -f /var/lib/apt/periodic/update-success-stamp ]; then
    last_update=$(stat -c %Y /var/lib/apt/periodic/update-success-stamp 2>/dev/null || echo 0)
elif [ -f /var/cache/apt/pkgcache.bin ]; then
    last_update=$(stat -c %Y /var/cache/apt/pkgcache.bin 2>/dev/null || echo 0)
fi

if [ "$last_update" -gt 0 ]; then
    now=$(date +%s)
    diff_sec=$(( now - last_update ))
    diff_days=$(( diff_sec / 86400 ))

    if [ "$diff_days" -ge "$WARN_DAYS" ]; then
        echo "Обновление: ${diff_days}д назад ⚠️  пора обновиться"
    else
        echo "Обновление: ${diff_days}д назад ✓"
    fi
else
    echo "Обновление: нет данных"
fi

# --- Проверка ядра ---
current_kernel=$(uname -r)
latest_kernel=$(ls -1t /boot/vmlinuz-* 2>/dev/null | head -1 | sed 's|/boot/vmlinuz-||')

if [ -z "$latest_kernel" ]; then
    # Нет файлов в /boot (контейнер?) — пропускаем
    exit 0
fi

if [ "$current_kernel" != "$latest_kernel" ]; then
    echo "Ядро: ребут (${current_kernel} → ${latest_kernel})"
else
    echo "Ядро: актуально ✓"
fi
