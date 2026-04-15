#!/bin/bash
# TITLE: Курс доллара (USD/RUB)
# Виджет для дашборда LumaxADM: показывает курс доллара к рублю.
#
# КАК НАСТРОИТЬ ПОД СЕБЯ:
#   - Хочешь евро — поменяй USD на EUR в API_URL.
#   - Лейбл "USD/RUB" можно переименовать, главное оставить двоеточие.

# Способ 1: ЦБ РФ (XML API)
rate=$(curl -s --connect-timeout 3 --max-time 5 "https://www.cbr.ru/scripts/XML_daily.asp" 2>/dev/null \
    | grep -A1 "USD" | grep -o '<Value>[^<]*' | cut -d'>' -f2 | tr ',' '.')

# Способ 2: fallback на открытый JSON API
if [ -z "$rate" ]; then
    rate=$(curl -s --connect-timeout 3 --max-time 5 \
        "https://api.exchangerate-api.com/v4/latest/USD" 2>/dev/null \
        | grep -o '"RUB":[0-9.]*' | cut -d: -f2)
fi

if [ -z "$rate" ]; then
    echo "USD/RUB: нет данных"
    exit 0
fi

rate_short=$(printf "%.2f" "$rate" 2>/dev/null || echo "$rate")
echo "USD/RUB: ${rate_short}₽"
