#!/bin/sh

# OpenWRT Configuration Script
# Provides multiple modes for system management and update

# Configuration variables
ZAPRET_LUCI_PKG="luci-app-zapret_72.20251227-r1_all.ipk"
ZAPRET_PKG="zapret_72.20251227-r1_mipsel_24kc.ipk"
ZAPRET_BASE_URL="https://github.com/Prianik/myVPN/raw/refs/heads/main/z"
DNS_FILES_URL="https://raw.githubusercontent.com/Prianik/myVPN/refs/heads/main"
BACKUP_DIR="/root"
BACKUP_FILE="$BACKUP_DIR/config_backup.tar.gz"

# Download retry parameters
MAX_RETRIES=3
RETRY_SLEEP=2

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️ $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Error handling function
handle_error() {
    log_error "Script failed at line $1 with exit code $2"
    exit $2
}

trap 'handle_error $LINENO $?' ERR

# Check internet connectivity
check_internet() {
    if ! ping -c 1 -W 3 github.com >/dev/null 2>&1; then
        log_error "No internet connection. Please check your network."
        exit 1
    fi
}

# Download file with retry
download_file() {
    local url=$1
    local filename=$2
    local retry_count=0

    while [ $retry_count -lt $MAX_RETRIES ]; do
        if wget --show-progress -q "$url" -O "$filename"; then
            return 0
        fi
        retry_count=$((retry_count + 1))
        log_warning "Download failed, retry $retry_count/$MAX_RETRIES..."
        sleep $RETRY_SLEEP
    done

    log_error "Failed to download: $url"
    return 1
}

# Helper: Copy config files manually
copy_config_files() {
    local src_dir=$1
    local dst_dir=$2
    local files="/etc/config/network /etc/config/wireless"
    local file

    for file in $files; do
        if [ -f "${src_dir}/$(basename "$file")" ]; then
            cp "${src_dir}/$(basename "$file")" "$dst_dir/"
        fi
    done
}

# Backup network and WiFi configuration
backup_config() {
    log_info "Creating backup of network configuration..."

    mkdir -p "$BACKUP_DIR"
    local config_files="/etc/config/network /etc/config/wireless"

    if ! tar -czf "$BACKUP_FILE" $config_files 2>/dev/null; then
        log_warning "Failed to create backup archive, copying files manually..."
        copy_config_files "/etc/config" "$BACKUP_DIR"
    fi

    if [ -f "$BACKUP_FILE" ] || { [ -f "$BACKUP_DIR/network" ] && [ -f "$BACKUP_DIR/wireless" ]; }; then
        log_success "Configuration backup created at $BACKUP_FILE"
        echo "Please download the backup file via SCP!"
    else
        log_error "Backup failed. No backup files found."
        exit 1
    fi
}

# Restore network and WiFi configuration from backup
restore_config() {
    log_info "Restoring network configuration from backup..."

    if [ ! -f "$BACKUP_FILE" ]; then
        log_warning "Backup archive $BACKUP_FILE not found. Trying manual restore..."
        if [ -f "$BACKUP_DIR/network" ] && [ -f "$BACKUP_DIR/wireless" ]; then
            copy_config_files "$BACKUP_DIR" "/etc/config"
            log_info "Manual restore completed."
        else
            log_error "No backup files found to restore."
            return 1
        fi
    else
        if ! tar -xzf "$BACKUP_FILE" -C / 2>/dev/null; then
            log_warning "Failed to extract backup archive, trying manual restore..."
            copy_config_files "$BACKUP_DIR" "/etc/config"
        fi
    fi

    /etc/init.d/network restart
    /etc/init.d/firewall restart
    /etc/init.d/dnsmasq restart

    log_success "Configuration restored successfully."
    rm -f "$BACKUP_FILE"
    log_info "Backup file deleted after successful restore."
}

# Reset to factory defaults
reset_to_factory() {
    log_info "Resetting to factory defaults..."
    backup_config

    log_warning "THIS WILL RESET ALL SETTINGS TO FACTORY DEFAULTS!"
    log_warning "All current configurations will be lost!"

    read -p "Are you sure you want to continue? (y/N): " confirm
    case "$confirm" in
        y|Y|yes|YES)
            log_info "Performing factory reset..."
            firstboot -y && reboot
            ;;
        *)
            log_info "Factory reset cancelled."
            return 1
            ;;
    esac
}

# Full automatic install mode (previously option 1)
full_auto_install_mode() {
    log_info "FULL AUTOMATIC INSTALL MODE SELECTED"

    # Handle WiFi parameters
    local wifi_params=""
    if [ $# -ge 3 ]; then
        wifi_params="$1 $2 $3"
    fi

    update_mode

    if [ -n "$wifi_params" ]; then
        system_config_mode $wifi_params
    else
        system_config_mode
    fi

    log_success "Full automatic install completed successfully!"
}

# Full automatic update mode (previously option 2)
update_mode() {
    log_info "FULL AUTOMATIC UPDATE MODE SELECTED"
    check_internet

    log_info "Updating package lists..."
    if ! opkg update; then
        log_error "Failed to update package lists. Check internet connection or repository URLs."
        exit 1
    fi

    for pkg in ca-certificates wget-ssl; do
        if ! opkg list-installed | grep -q "^$pkg"; then
            log_info "Installing $pkg..."
            opkg install "$pkg" || { log_error "Failed to install $pkg"; exit 1; }
        fi
    done

    log_info "Removing nfqws-keenetic packages..."
    if opkg list-installed | grep -q nfqws-keenetic; then
        opkg remove nfqws-keenetic* || log_warning "Failed to remove nfqws-keenetic packages (continuing anyway)"
    else
        log_info "nfqws-keenetic packages not found. Skipping removal."
    fi

    log_info "Upgrading installed packages..."
    upgradable_pkgs=$(opkg list-upgradable | awk '{print $1}')
    if [ -n "$upgradable_pkgs" ]; then
        echo "$upgradable_pkgs" | xargs -r opkg upgrade
    else
        log_info "No packages to upgrade."
    fi

    update_zapret
    update_instagram_dns

    log_info "Updating/Installing https-dns-proxy..."
    if opkg list-installed | grep -q https-dns-proxy; then
        log_info "https-dns-proxy is installed. Proceeding with update..."
        opkg install --force-reinstall https-dns-proxy luci-app-https-dns-proxy || {
            log_error "Failed to update https-dns-proxy"
            exit 1
        }
    else
        log_info "https-dns-proxy is not installed. Proceeding with installation..."
        opkg install https-dns-proxy luci-app-https-dns-proxy || {
            log_error "Failed to install https-dns-proxy"
            exit 1
        }
    fi

    service rpcd restart || log_warning "Failed to restart rpcd (continuing anyway)"
    log_success "Full automatic update completed successfully!"
}

# Update or install ZAPRET
update_zapret() {
    log_info "Updating/Installing ZAPRET..."
    local zapret_installed=$(opkg list-installed | grep -q zapret && echo "yes" || echo "no")

    if [ "$zapret_installed" = "yes" ]; then
        log_info "ZAPRET is installed. Proceeding with update..."
    else
        log_info "ZAPRET is not installed. Proceeding with installation..."
    fi

    for pkg in "$ZAPRET_PKG" "$ZAPRET_LUCI_PKG"; do
        download_file "$ZAPRET_BASE_URL/$pkg" "$pkg" || exit 1
    done

    opkg install --force-reinstall "$ZAPRET_PKG" "$ZAPRET_LUCI_PKG" || {
        log_error "Failed to install/update ZAPRET"
        rm -f "$ZAPRET_PKG" "$ZAPRET_LUCI_PKG"
        exit 1
    }

    rm -f "$ZAPRET_PKG" "$ZAPRET_LUCI_PKG"
}

# Update Instagram DNS for ZAPRET
update_instagram_dns() {
    if [ -d "/opt/zapret" ]; then
        log_info "Updating Instagram DNS..."
        for file in dns.txt dns-ext.txt ip.txt; do
            download_file "$DNS_FILES_URL/$file" "$file" || exit 1
        done

        cat dns.txt >> /opt/zapret/ipset/zapret-hosts-user.txt
        cat ip.txt >> /opt/zapret/ipset/zapret-ip-user.txt
        cat dns-ext.txt >> /opt/zapret/ipset/zapret-hosts-user-exclude.txt

        rm -f dns.txt ip.txt dns-ext.txt

        service zapret restart || log_warning "Failed to restart ZAPRET service (continuing anyway)"
    else
        log_info "ZAPRET directory not found. Skipping DNS update."
    fi
}

# Combined ZAPRET and Instagram DNS update/install mode (formerly 4)
zapret_dns_mode() {
    log_info "ZAPRET and Instagram DNS update/install mode selected"
    check_internet
    update_zapret
    update_instagram_dns
    log_success "ZAPRET and Instagram DNS update/install completed successfully!"
}

# System configuration mode (previously option 3)
system_config_mode() {
    log_info "Configuring timezone and time..."
    uci set system.@system[0].zonename='Europe/Moscow'
    uci set system.@system[0].timezone='MSK-3'
    uci commit system || { log_error "Failed to commit system settings"; exit 1; }

    /etc/init.d/sysntpd restart || log_warning "Failed to restart sysntpd (continuing anyway)"

    log_info "Setting up crontab..."
    {
        echo "#31 0 * * 1 /usr/bin/wget -qO - https://github.com/Prianik/myVPN/raw/refs/heads/main/z/update.sh | sh"
        echo "#30 0 * * 0 /usr/bin/wget -qO - https://github.com/Prianik/myVPN/raw/refs/heads/main/z/update-dns.sh | sh"
        echo "30 3 * * * /sbin/reboot"
    } >> /etc/crontabs/root

    /etc/init.d/cron restart || log_warning "Failed to restart cron service (continuing anyway)"

    log_info "SYSTEM CONFIGURATION MODE SELECTED"

    # Restore config if backup exists
    if [ -f "$BACKUP_FILE" ]; then
        log_info "Backup file detected. Restoring network settings now..."
        restore_config
    else
        local NameSSID0
        local NameSSID1
        local WiFiKey

        if [ $# -eq 3 ]; then
            NameSSID0=$1
            NameSSID1=$2
            WiFiKey=$3
        else
            log_info "No Wi-Fi parameters provided. Prompting for input..."
            read -p "Enter NameSSID for WiFi5: " NameSSID0
            read -p "Enter NameSSID for WiFi2.4: " NameSSID1
            read -s -p "Enter Wi-Fi password: " WiFiKey
            echo
        fi

        # Simple validation
        if [ -z "$NameSSID0" ] || [ -z "$NameSSID1" ] || [ -z "$WiFiKey" ]; then
            log_error "Wi-Fi parameters cannot be empty."
            exit 1
        fi

        log_info "Configuring Wi-Fi..."
        uci set wireless.@wifi-iface[0].device='radio0'
        uci set wireless.@wifi-iface[0].mode='ap'
        uci set wireless.@wifi-iface[0].disabled=0
        uci set wireless.@wifi-iface[0].ssid="$NameSSID0"
        uci set wireless.@wifi-iface[0].network='lan'
        uci set wireless.@wifi-iface[0].encryption='psk2'
        uci set wireless.@wifi-iface[0].key="$WiFiKey"
        uci set wireless.radio0.disabled=0

        uci set wireless.@wifi-iface[1].device='radio1'
        uci set wireless.@wifi-iface[1].mode='ap'
        uci set wireless.@wifi-iface[1].disabled=0
        uci set wireless.@wifi-iface[1].ssid="$NameSSID1"
        uci set wireless.@wifi-iface[1].network='lan'
        uci set wireless.@wifi-iface[1].encryption='psk2'
        uci set wireless.@wifi-iface[1].key="$WiFiKey"
        uci set wireless.radio1.disabled=0

        uci commit wireless || { log_error "Failed to commit Wi-Fi settings"; exit 1; }
        log_info "Wi-Fi configuration applied"

        log_info "Setting LAN IP to 172.16.1.1..."
        uci set network.lan.ipaddr='172.16.1.1'
        uci commit network || { log_error "Failed to commit network settings"; exit 1; }

        if ! /etc/init.d/network restart; then
            log_warning "Failed to restart network (continuing anyway)"
        fi

        log_info "Local network IP address changed to 172.16.1.1"
    fi

    # Clean up temporary files
    rm -f ./*

    log_success "System configuration completed successfully!"
}

# Factory reset with restore (option 5)
factory_reset_with_restore_mode() {
    log_info "FACTORY RESET WITH RESTORE MODE SELECTED"
    backup_config

    echo "Backup file is stored at $BACKUP_FILE."
    echo "Please download it (e.g., using scp) before proceeding with the factory reset."

    read -p "Press Enter to continue with the factory reset or Ctrl+C to cancel..."
    if reset_to_factory; then
        log_info "Waiting for system to reboot after factory reset..."
        log_info "After reboot, please run this script again to restore your configuration."
        exit 0
    else
        log_info "Factory reset cancelled. Proceeding with update and restore..."
    fi

    update_mode
    restore_config

    log_success "Factory reset with restore completed successfully!"
}

# Manual backup mode (new option 6)
manual_backup_mode() {
    log_info "MANUAL BACKUP MODE SELECTED"
    backup_config
    log_success "Manual backup completed successfully!"
}

# Restore network settings from backup manually (previously option 6, now 7)
manual_restore_mode() {
    log_info "MANUAL RESTORE MODE SELECTED"

    if [ -f "$BACKUP_FILE" ]; then
        log_info "Backup file detected. Restoring network settings now..."
        restore_config
    else
        log_error "Backup file $BACKUP_FILE not found. Cannot restore."
        exit 1
    fi
}

# Update installed packages (previously option 7, now 8)
update_installed_packages() {
    log_info "Updating package lists..."
    if ! opkg update; then
        log_error "Failed to update package lists."
        exit 1
    fi

    log_info "Upgrading installed packages..."
    upgradable_pkgs=$(opkg list-upgradable | cut -f 1 -d ' ')
    if [ -n "$upgradable_pkgs" ]; then
        echo "$upgradable_pkgs" | xargs -r opkg upgrade
        log_success "Package upgrade completed."
    else
        log_info "No packages to upgrade."
    fi
}

# Main menu
show_menu() {
    echo ""
    echo "=========================================="
    echo " OpenWRT Configuration Script"
    echo "=========================================="
    echo ""
    echo "Select mode:"
    echo "1) Full automatic INSTALL (update + configuration)"
    echo "2) Full automatic UPDATE (remove keenetic, update packages, ZAPRET, DNS, https-dns-proxy)"
    echo "3) System configuration (NET, WiFi, crontab)"
    echo "4) ZAPRET and Instagram DNS update/install"
    echo "5) Factory reset with restore (backup → reset → update → restore)"
    echo "6) Manual backup"
    echo "7) Restore network settings from backup"
    echo "8) Update installed packages"
    echo ""
    echo "Notes:"
    echo "- For modes 1 and 3, you can provide WiFi parameters as arguments:"
    echo "  $0 1 \"WiFi5_SSID\" \"WiFi2.4_SSID\" \"Password\""
    echo "  $0 3 \"WiFi5_SSID\" \"WiFi2.4_SSID\" \"Password\""
    echo "- Mode 1: Full installation (update + system configuration)"
    echo "- Mode 2: Only update packages and services"
    echo "- Mode 5: Backup config, reset to factory, update, then restore config"
    echo "- Mode 6: Manual backup of network settings"
    echo "- Mode 7: Manual restoration of network settings from backup"
    echo "- Mode 8: Update installed packages"
    echo ""
}

# Main execution
main() {
    show_menu

    read -rp "Enter your choice (1-8): " choice

    case $choice in
        1)
            full_auto_install_mode "$@"
            ;;
        2)
            update_mode
            ;;
        3)
            system_config_mode "$@"
            ;;
        4)
            zapret_dns_mode
            ;;
        5)
            factory_reset_with_restore_mode
            ;;
        6)
            manual_backup_mode
            ;;
        7)
            manual_restore_mode
            ;;
        8)
            update_installed_packages
            ;;
        *)
            log_error "Invalid choice. Please enter 1-8."
            exit 1
            ;;
    esac
}

main "$@"
