#!/bin/sh

# Script for configuring OpenWRT:
# - Update OPKG and installed packages
# - Install or update ZAPRET
# - Add DNS for Instagram
# - Install https-dns-proxy
# - Set timezone and time
# - Configure Wi-Fi
# - Change LAN IP address

# Reference links:
# https://github.com/Prianik/myVPN/raw/refs/heads/main/z/rt-z.sh
# https://github.com/remittor/zapret-openwrt/releases

# Update OPKG and install necessary packages
echo ""
echo ".......Updating OPKG......."
echo ""
opkg update
opkg install ca-certificates wget-ssl

# Update installed packages
echo ""
echo ".......Updating installed packages......."
echo ""
opkg list-upgradable | cut -f 1 -d ' ' | xargs -r opkg upgrade

# Identify the latest version of ZAPRET
echo ""
echo ".......Identifying the latest version of ZAPRET......."
wget -q https://github.com/Prianik/myVPN/raw/refs/heads/main/z/zver.txt
zver=$(cat zver.txt)
rm -f zver.txt
echo ""
echo "********Version ZAPRET******${zver}"
echo ""

# Install or update ZAPRET
echo ".......Installing ZAPRET version-${zver}......."
wget -q https://github.com/Prianik/myVPN/raw/refs/heads/main/z/luci-app-zapret_${zver}_all.ipk
wget -q https://github.com/Prianik/myVPN/raw/refs/heads/main/z/zapret_${zver}_mipsel_24kc.ipk

opkg install zapret_${zver}_mipsel_24kc.ipk
opkg install luci-app-zapret_${zver}_all.ipk
rm -f zapret_${zver}_mipsel_24kc.ipk
rm -f luci-app-zapret_${zver}_all.ipk

# Add DNS for Instagram
echo ""
echo ".......Adding DNS for Instagram......."
echo ""
wget -q https://raw.githubusercontent.com/Prianik/myVPN/refs/heads/main/dns.txt
cat dns.txt >> /opt/zapret/ipset/zapret-hosts-user.txt
rm -f dns.txt
service zapret restart

# Install https-dns-proxy
echo ""
echo ".......Installing https-dns-proxy......."
echo ""
opkg install https-dns-proxy
opkg install luci-app-https-dns-proxy
service rpcd restart

# Set up cron for automatic updates
echo ""
echo ".......Setting up crontab......."
echo ""
echo "31 0 * * 1 /usr/bin/wget -qO - https://github.com/Prianik/myVPN/raw/refs/heads/main/z/update.sh | sh" >> /etc/crontabs/root
/etc/init.d/cron restart

# Set timezone and time
echo ""
echo ".......Setting Timezone and time......."
echo ""
uci set system.@system[0].zonename='Europe/Moscow'
uci set system.@system[0].timezone='MSK-3'
uci commit system
/etc/init.d/sysntpd restart

# Configure Wi-Fi
echo ""
echo ".......Setting up Wi-Fi......."
echo ""
if [ $# -eq 3 ]; then
    echo ".......Wi-Fi parameters provided........"
    NameSSID0=$1  # Wi-Fi 5 GHz SSID
    NameSSID1=$2  # Wi-Fi 2.4 GHz SSID
    WiFiKey=$3    # Wi-Fi password
else
    echo ".......No Wi-Fi parameters provided. Prompting for input........"
    read -p "Enter NameSSID for WiFi5: " NameSSID0
    read -p "Enter NameSSID for WiFi2.4: " NameSSID1
    read -p "Enter Wi-Fi password: " WiFiKey
fi

# Configure Wi-Fi 5 GHz (radio0)
uci set wireless.@wifi-iface[0].device='radio0'
uci set wireless.@wifi-iface[0].mode='ap'
uci set wireless.@wifi-iface[0].disabled=0
uci set wireless.@wifi-iface[0].ssid="$NameSSID0"
uci set wireless.@wifi-iface[0].network='lan'
uci set wireless.@wifi-iface[0].encryption='psk2'
uci set wireless.@wifi-iface[0].key="$WiFiKey"
uci set wireless.radio0.disabled=0

# Configure Wi-Fi 2.4 GHz (radio1)
uci set wireless.@wifi-iface[1].device='radio1'
uci set wireless.@wifi-iface[1].mode='ap'
uci set wireless.@wifi-iface[1].disabled=0
uci set wireless.@wifi-iface[1].ssid="$NameSSID1"
uci set wireless.@wifi-iface[1].network='lan'
uci set wireless.@wifi-iface[1].encryption='psk2'
uci set wireless.@wifi-iface[1].key="$WiFiKey"
uci set wireless.radio1.disabled=0

# Apply Wi-Fi settings
uci commit wireless
echo ""
echo ".......Wi-Fi configuration applied........"
echo ""

# Set LAN IP address
echo ""
echo ".......Setting LAN IP to 172.16.1.1......."
echo ""
uci set network.lan.ipaddr='172.16.1.1'
uci commit network
/etc/init.d/network restart
echo ""
echo ".......Local network IP address changed to 172.16.1.1........"
echo ""

# Clean up temporary files
rm -f ./*

# Script completion
echo ""
echo ".......Script execution completed successfully!......."
echo ""
