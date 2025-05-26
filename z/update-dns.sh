#!/bin/sh

if [wget -q https://raw.githubusercontent.com/Prianik/myVPN/refs/heads/main/dns.txt] &&  [wget -q https://raw.githubusercontent.com/Prianik/myVPN/refs/heads/main/ip.txt]
then
    if [ -f dns.txt ] && [ -f ip.txt ]; then
        cat dns.txt > /opt/zapret/ipset/zapret-hosts-user.txt
        cat ip.txt > /opt/zapret/ipset/zapret-ip-user.txt
        rm -f dns.txt ip.txt
        service zapret restart
    else
        echo "Загруженные файлы не найдены"
        rm -f dns.txt ip.txt
        exit 1
    fi
else
    echo "Ошибка загрузки файлов"
    rm -f dns.txt ip.txt
    exit 1
fi
