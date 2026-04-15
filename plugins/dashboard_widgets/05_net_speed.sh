#!/bin/bash
# TITLE: Скорость сети (live)
# Виджет для дашборда LumaxADM: показывает текущую скорость сети.
#
# КАК НАСТРОИТЬ ПОД СЕБЯ:
#   - Интерфейс определяется автоматически (default route).
#   - Если хочешь конкретный интерфейс — замени IFACE="eth0" ниже.

# Определяем основной интерфейс
IFACE=$(ip route show default 2>/dev/null | awk '{print $5}' | head -1)
if [ -z "$IFACE" ]; then
    echo "Сеть: интерфейс не найден"
    exit 0
fi

# Первый замер
RX1=$(cat /sys/class/net/"$IFACE"/statistics/rx_bytes 2>/dev/null || echo 0)
TX1=$(cat /sys/class/net/"$IFACE"/statistics/tx_bytes 2>/dev/null || echo 0)

sleep 1

# Второй замер
RX2=$(cat /sys/class/net/"$IFACE"/statistics/rx_bytes 2>/dev/null || echo 0)
TX2=$(cat /sys/class/net/"$IFACE"/statistics/tx_bytes 2>/dev/null || echo 0)

# Разница в байтах/сек → Mbit/s
RX_DIFF=$(( RX2 - RX1 ))
TX_DIFF=$(( TX2 - TX1 ))

# Конвертируем в удобный формат
_format_speed() {
    local bytes=$1
    if [ "$bytes" -ge 131072 ]; then
        # >= 1 Mbit/s, показываем в Mbit
        local mbits=$(echo "scale=1; $bytes * 8 / 1048576" | bc 2>/dev/null || echo "0")
        echo "${mbits} Mb/s"
    else
        # < 1 Mbit/s, показываем в Kbit
        local kbits=$(( bytes * 8 / 1024 ))
        echo "${kbits} Kb/s"
    fi
}

DL=$(_format_speed "$RX_DIFF")
UL=$(_format_speed "$TX_DIFF")

echo "Сеть: ↓${DL} ↑${UL}"
