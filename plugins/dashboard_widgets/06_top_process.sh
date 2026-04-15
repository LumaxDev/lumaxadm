#!/bin/bash
# TITLE: Топ процесс по CPU
# Виджет для дашборда LumaxADM: показывает самый прожорливый процесс.
#
# КАК НАСТРОИТЬ ПОД СЕБЯ:
#   - Если хочешь топ по RAM — замени --sort=-%cpu на --sort=-%mem.

TOP_LINE=$(ps aux --sort=-%cpu 2>/dev/null | awk 'NR==2 {print $11, $3}')

if [ -z "$TOP_LINE" ]; then
    echo "Топ процесс: нет данных"
    exit 0
fi

PROC_NAME=$(echo "$TOP_LINE" | awk '{print $1}')
PROC_CPU=$(echo "$TOP_LINE" | awk '{print $2}')

# Убираем путь, оставляем только имя
PROC_SHORT=$(basename "$PROC_NAME" 2>/dev/null || echo "$PROC_NAME")

echo "Жрёт CPU: ${PROC_SHORT} (${PROC_CPU}%)"
