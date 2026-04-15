#!/bin/bash
# TITLE: Статус ICMP/IPv6
# Виджет для дашборда LumaxADM: показывает включён ли пинг и IPv6.

# --- ICMP Ping ---
ping_status="?"
if [ -f "/etc/ufw/before.rules" ]; then
    if grep -q "ufw-before-input -p icmp --icmp-type echo-request -j DROP" /etc/ufw/before.rules; then
        ping_status="OFF"
    else
        ping_status="ON"
    fi
fi

# --- IPv6 ---
ipv6_status="?"
ipv6_all=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null)
if [ "$ipv6_all" = "1" ]; then
    ipv6_status="OFF"
else
    ipv6_status="ON"
fi

echo "ICMP/IPv6: Ping=${ping_status}  IPv6=${ipv6_status}"
