#!/bin/sh

# OpenWRT Configuration Script
# Provides two modes:
# 1. Update mode - updates packages without changing network settings
# 2. Clean install mode - full system configuration with network setup

# Exit immediately if any command fails
set -e

# Function for update mode
update_mode() {
    echo ""
    echo ".......UPDATE MODE SELECTED......."
    echo ""
    
    # Update OPKG and install necessary packages
    echo ".......Updating package lists......."
    if ! opkg update; then
        echo "❌ Error: Failed to update package lists. Check internet connection or repo URLs."
        exit 1
    fi

    opkg install ca-certificates wget-ssl || {
        echo "❌ Error: Failed to install required packages (ca-certificates, wget-ssl)."
        exit 1
    }

    # Update installed packages
    echo ""
    echo ".......Upgrading installed packages......."
    echo ""
    opkg list-upgradable | cut -f 1 -d ' ' | xargs -r opkg upgrade

    # Update ZAPRET if installed
    if opkg list-installed | grep -q zapret; then
        echo ""
        echo ".......Updating ZAPRET......."
        echo ""
        #-----------------------------------------------------------
        vluci=luci-app-zapret_71.20250708-r1_all.ipk
        vzapret=zapret_71.20250708_mipsel_24kc.ipk
        #-----------------------------------------------------------

        if ! wget -q "https://github.com/Prianik/myVPN/raw/refs/heads/main/z/${vluci}" || \
           ! wget -q "https://github.com/Prianik/myVPN/raw/refs/heads/main/z/${vzapret}"; then
            echo "❌ Error: Failed to download ZAPRET packages."
            exit 1
        fi

        if ! opkg install --force-reinstall "${vzapret}" || \
           ! opkg install --force-reinstall "${vluci}"; then
            echo "❌ Error: Failed to update ZAPRET."
            exit 1
        fi
        rm -f ${vzapret}
        rm -f ${vluci}
    fi

    # Update DNS for Instagram if ZAPRET is installed
    if [ -d "/opt/zapret" ]; then
        echo ""
        echo ".......Updating Instagram DNS......."
        echo ""
        if ! wget -q https://raw.githubusercontent.com/Prianik/myVPN/refs/heads/main/dns.txt || \
           ! wget -q https://raw.githubusercontent.com/Prianik/myVPN/refs/heads/main/ip.txt; then
            echo "❌ Error: Failed to download DNS/IP lists."
            exit 1
        fi
        cat dns.txt >> /opt/zapret/ipset/zapret-hosts-user.txt || exit 1
        cat ip.txt >> /opt/zapret/ipset/zapret-ip-user.txt || exit 1
        rm -f dns.txt
        rm -f ip.txt
        service zapret restart || {
            echo "⚠ Warning: Failed to restart ZAPRET service (continuing anyway)."
        }
    fi

    # Update https-dns-proxy if installed
    if opkg list-installed | grep -q https-dns-proxy; then
        echo ""
        echo ".......Updating https-dns-proxy......."
        echo ""
        if ! opkg install --force-reinstall https-dns-proxy || ! opkg install --force-reinstall luci-app-https-dns-proxy; then
            echo "❌ Error: Failed to update https-dns-proxy."
            exit 1
        fi
        service rpcd restart || {
            echo "⚠ Warning: Failed to restart rpcd (continuing anyway)."
        }
    fi

    echo ""
    echo "✅ Update completed successfully!......."
    echo ""
}

# Function for clean install mode
clean_install_mode() {
    echo ""
    echo ".......CLEAN INSTALL MODE SELECTED......."
    echo ""
    
    # Run all update steps first
    update_mode

    # Set timezone and time
    echo ""
    echo ".......Configuring timezone and time......."
    echo ""
    uci set system.@system[0].zonename='Europe/Moscow'
    uci set system.@system[0].timezone='MSK-3'
    uci commit system || exit 1
    /etc/init.d/sysntpd restart || {
        echo "⚠ Warning: Failed to restart sysntpd (continuing anyway)."
    }

    # Configure Wi-Fi
    echo ""
    echo ".......Configuring Wi-Fi......."
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
    uci commit wireless || {
        echo "❌ Error: Failed to commit Wi-Fi settings."
        exit 1
    }
    echo ""
    echo ".......Wi-Fi configuration applied........"
    echo ""

    # Set LAN IP address
    echo ""
    echo ".......Setting LAN IP to 172.16.1.1......."
    echo ""
    uci set network.lan.ipaddr='172.16.1.1'
    uci commit network || {
        echo "❌ Error: Failed to commit network settings."
        exit 1
    }
    if ! /etc/init.d/network restart; then
        echo "⚠ Warning: Failed to restart network (continuing anyway)."
    fi
    echo ""
    echo ".......Local network IP address changed to 172.16.1.1........"
    echo ""

    # Clean up temporary files
    rm -f ./*

    echo ""
    echo "✅ Clean installation completed successfully!......."
    echo ""
}

# Main menu
echo ""
echo "=========================================="
echo " OpenWRT Configuration Script"
echo "=========================================="
echo ""
echo "Select mode:"
echo "1) Update (package updates only)"
echo "2) Clean install (full system configuration)"
echo ""
read -p "Enter your choice (1 or 2): " choice

case $choice in
    1)
        update_mode
        ;;
    2)
        clean_install_mode "$@"
        ;;
    *)
        echo "❌ Invalid choice. Please enter 1 or 2."
        exit 1
        ;;
esac
