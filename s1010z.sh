#!/bin/sh

echo ".......Updating OPKG and updating installed packages"
opkg update 
opkg install ca-certificates wget-ssl
opkg list-upgradable | cut -f 1 -d ' ' | xargs -r opkg upgrade

echo ".......Installed ZAPRET"
wget  https://github.com/Prianik/myVPN/raw/refs/heads/main/z/luci-app-zapret_70.20250116_all.ipk
wget  https://github.com/Prianik/myVPN/raw/refs/heads/main/z/zapret_70.20250116_mipsel_24kc.ipk
opkg install zapret_70.20250116_mipsel_24kc.ipk
opkg install luci-app-zapret_70.20250116_all.ipk
service zapret restart

echo ".......Installed https-dns-proxy"
opkg install https-dns-proxy
opkg install luci-app-https-dns-proxy
service rpcd restart

echo ".......SET Timezone and time"
uci set system.@system[0].zonename='Europe/Moscow'
uci set system.@system[0].timezone='MSK-3'
uci commit system
/etc/init.d/sysntpd restart

rm *