#!/bin/bash
# TITLE: Курс доллара (USD/RUB)
# Виджет для дашборда LumaxADM: показывает курс доллара к рублю.
#
# КАК НАСТРОИТЬ ПОД СЕБЯ:
#   - Хочешь евро — поменяй USD на EUR в API_URL.
#   - Лейбл "USD/RUB" можно переименовать, главное оставить двоеточие.

API_URL="https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.json"

result=$(curl -s --connect-timeout 3 --max-time 5 "$API_URL" 2>/dev/null)

if [ -z "$result" ]; then
    echo "USD/RUB: нет связи"
    exit 0
fi

rate=$(echo "$result" | grep -o '"rub":[0-9.]*' | cut -d: -f2)

if [ -z "$rate" ]; then
    echo "USD/RUB: нет данных"
    exit 0
fi

# Округляем до 2 знаков
rate_short=$(printf "%.2f" "$rate" 2>/dev/null || echo "$rate")

echo "USD/RUB: ${rate_short}₽"
