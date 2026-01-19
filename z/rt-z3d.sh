#!/bin/sh

# ==============================================================================
# OpenWRT Configuration Script (No LuCI Menu Version)
#
# Description:
#   This script provides a comprehensive menu-driven interface for managing,
#   updating, and configuring an OpenWRT system. It includes features for
#   installing specific packages (like Zapret, ttyd), managing network settings,
#   handling backups, and configuring web-based terminal access.
#
#   NOTE: This version does NOT create custom menu entries in the LuCI web interface.
#
# Author: [Your Name/Organization]
# Date: [Current Date]
# ==============================================================================

# ==============================================================================
# Configuration Variables
# ==============================================================================

# URLs for downloading Zapret packages and DNS lists
ZAPRET_BASE_URL="https://github.com/Prianik/myVPN/raw/refs/heads/main/z"
ZAPRET_VER_FILE="ZAPRET_VER.txt"
DNS_FILES_URL="https://raw.githubusercontent.com/Prianik/myVPN/refs/heads/main"

# Backup configuration
BACKUP_DIR="/root"
BACKUP_FILE="$BACKUP_DIR/config_backup.tar.gz"

# Download retry parameters to ensure reliability
MAX_RETRIES=3
RETRY_SLEEP=2

# ==============================================================================
# Color Codes for Output
# ==============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ==============================================================================
# Logging Functions
# ==============================================================================

# Log informational messages in blue
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Log success messages in green
log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Log warning messages in yellow
log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Log error messages in red
log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# ==============================================================================
# Error Handling
# ==============================================================================

# Function to handle errors caught by the 'trap' command
# Arguments:
#   $1: Line number where the error occurred
#   $2: Exit code of the command that failed
handle_error() {
    log_error "Script failed at line $1 with exit code $2"
    exit $2
}

# Set up a trap to call handle_error on any command failure
# Note: 'ERR' trap is not standard POSIX sh but works in many shells. 
trap 'handle_error $LINENO $?' ERR

# ==============================================================================
# Helper Functions
# ==============================================================================

# Check for active internet connection by pinging github.com
check_internet() {
    if ! ping -c 1 -W 3 github.com >/dev/null 2>&1; then
        log_error "No internet connection. Please check your network."
        exit 1
    fi
}

# Download a file with automatic retries
# Arguments:
#   $1: URL to download
#   $2: Output filename
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

# Manually copy configuration files from source to destination
# Arguments:
#   $1: Source directory
#   $2: Destination directory
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

# ==============================================================================
# Backup and Restore Functions
# ==============================================================================

# Create a backup of critical network and wireless configurations
backup_config() {
    log_info "Creating backup of network configuration..."

    mkdir -p "$BACKUP_DIR"
    local config_files="/etc/config/network /etc/config/wireless"

    # Try to create a tarball
    if ! tar -czf "$BACKUP_FILE" $config_files 2>/dev/null; then
        log_warning "Failed to create backup archive, copying files manually..."
        copy_config_files "/etc/config" "$BACKUP_DIR"
    fi

    # Verify backup success
    if [ -f "$BACKUP_FILE" ] || { [ -f "$BACKUP_DIR/network" ] && [ -f "$BACKUP_DIR/wireless" ]; }; then
        log_success "Configuration backup created at $BACKUP_FILE"
        echo "Please download the backup file via SCP!"
    else
        log_error "Backup failed. No backup files found."
        exit 1
    fi
}

# Restore network configuration from a previously created backup
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
        # Extract archive to root
        if ! tar -xzf "$BACKUP_FILE" -C / 2>/dev/null; then
            log_warning "Failed to extract backup archive, trying manual restore..."
            copy_config_files "$BACKUP_DIR" "/etc/config"
        fi
    fi

    # Restart network services to apply changes
    /etc/init.d/network restart
    /etc/init.d/firewall restart
    /etc/init.d/dnsmasq restart

    log_success "Configuration restored successfully."
    rm -f "$BACKUP_FILE"
    log_info "Backup file deleted after successful restore."
}

# Perform a factory reset, preserving the current configuration via backup/restore
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

# ==============================================================================
# Installation and Update Logic
# ==============================================================================

# Mode 1: Full Automatic Install
# Combines update and system configuration
full_auto_install_mode() {
    log_info "FULL AUTOMATIC INSTALL MODE SELECTED"

    # Handle optional WiFi parameters passed as arguments
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

# Mode 2: Full Automatic Update
# Updates system packages, removes conflicting ones, and installs/updates tools
update_mode() {
    log_info "FULL AUTOMATIC UPDATE MODE SELECTED"
    check_internet

    log_info "Updating package lists..."
    if ! opkg update; then
        log_error "Failed to update package lists. Check internet connection or repository URLs."
        exit 1
    fi

    # Install essential SSL support tools
    for pkg in ca-certificates wget-ssl qrencode; do
        if ! opkg list-installed | grep -q "^$pkg"; then
            log_info "Installing $pkg..."
            opkg install "$pkg" || { log_error "Failed to install $pkg"; exit 1; }
        fi
    done

    # Remove conflicting packages (e.g., nfqws-keenetic)
    log_info "Removing nfqws-keenetic packages..."
    if opkg list-installed | grep -q nfqws-keenetic; then
        opkg remove nfqws-keenetic* || log_warning "Failed to remove nfqws-keenetic packages (continuing anyway)"
    else
        log_info "nfqws-keenetic packages not found. Skipping removal."
    fi

    # Upgrade all upgradable packages
    log_info "Upgrading installed packages..."
    upgradable_pkgs=$(opkg list-upgradable | awk '{print $1}')
    if [ -n "$upgradable_pkgs" ]; then
        echo "$upgradable_pkgs" | xargs -r opkg upgrade
    else
        log_info "No packages to upgrade."
    fi

    # Update specific tools
    update_zapret
    update_instagram_dns
    update_dns_proxy

    # Restart RPC daemon
    service rpcd restart || log_warning "Failed to restart rpcd (continuing anyway)"
    log_success "Full automatic update completed successfully!"
}

# Mode 10: Install/Update ttyd (Web Terminal)
ttyd_install() {
    log_info "Updating/Installing ttyd..."
    local ttyd_installed=$(opkg list-installed | grep -q ttyd && echo "yes" || echo "no")

    log_info "Updating package lists..."
    if ! opkg update; then
        log_error "Failed to update package lists. Check internet connection or repository URLs."
        exit 1
    fi

    if [ "$ttyd_installed" = "yes" ]; then
        log_info "ttyd is installed. Proceeding with update..."
        opkg install --force-reinstall ttyd luci-app-ttyd || {
            log_error "Failed to update ttyd"
            exit 1
        }
    else
        log_info "ttyd is not installed. Proceeding with installation..."
        opkg install ttyd luci-app-ttyd || {
            log_error "Failed to install ttyd"
            exit 1
        }
    fi

    log_success "ttyd installation/update completed successfully!"
}

# Update or install ZAPRET package
update_zapret() {
    log_info "Updating/Installing ZAPRET..."
    local zapret_installed=$(opkg list-installed | grep -q zapret && echo "yes" || echo "no")

    if [ "$zapret_installed" = "yes" ]; then
        log_info "ZAPRET is installed. Proceeding with update..."
    else
        log_info "ZAPRET is not installed. Proceeding with installation..."
    fi

    # Download version file to determine which packages to fetch
    log_info "Downloading ZAPRET version file..."
    rm -f "$ZAPRET_VER_FILE"
    download_file "$ZAPRET_BASE_URL/$ZAPRET_VER_FILE" "$ZAPRET_VER_FILE" || {
        log_error "Failed to download $ZAPRET_VER_FILE"
        exit 1
    }

    # Load version variables (using 'source' via '.')
    SCRIPT_DIR="$(pwd)"
    # shellcheck disable=SC1090
    . "$SCRIPT_DIR/$ZAPRET_VER_FILE" || {
        log_error "Failed to source $ZAPRET_VER_FILE"
        exit 1
    }

    # Download the actual package files defined in the version file
    for pkg in "$ZAPRET_PKG" "$ZAPRET_LUCI_PKG"; do
        download_file "$ZAPRET_BASE_URL/$pkg" "$pkg" || exit 1
    done

    # Install the packages
    opkg install --force-reinstall "$ZAPRET_PKG" "$ZAPRET_LUCI_PKG" || {
        log_error "Failed to install/update ZAPRET"
        rm -f "$ZAPRET_PKG" "$ZAPRET_LUCI_PKG"
        exit 1
    }

    # Clean up downloaded package files
    rm -f "$ZAPRET_PKG" "$ZAPRET_LUCI_PKG"
    log_success "ZAPRET installation/update completed successfully!"
}

# Update DNS lists for ZAPRET (specifically for Instagram/Social Media)
update_instagram_dns() {
    if [ -d "/opt/zapret" ]; then
        log_info "Updating Instagram DNS..."
        for file in dns.txt dns-ext.txt ip.txt; do
            download_file "$DNS_FILES_URL/$file" "$file" || exit 1
        done

        # Append downloaded lists to ZAPRET's ipsets
        cat dns.txt >> /opt/zapret/ipset/zapret-hosts-user.txt
        cat ip.txt >> /opt/zapret/ipset/zapret-ip-user.txt
        cat dns-ext.txt >> /opt/zapret/ipset/zapret-hosts-user-exclude.txt

        rm -f dns.txt ip.txt dns-ext.txt

        service zapret restart || log_warning "Failed to restart ZAPRET service (continuing anyway)"
    else
        log_info "ZAPRET directory not found. Skipping DNS update."
    fi
}

# Mode 9: Update/Install https-dns-proxy
update_dns_proxy() {
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
}

# Mode 4: Combined ZAPRET and DNS update
zapret_dns_mode() {
    log_info "ZAPRET and Instagram DNS update/install mode selected"
    check_internet
    update_zapret
    update_instagram_dns
    log_success "ZAPRET and Instagram DNS update/install completed successfully!"
}

# ==============================================================================
# System Configuration Functions
# ==============================================================================

# Mode 3: Configure System Settings (Timezone, Cron, WiFi, Network)
system_config_mode() {
    log_info "Configuring timezone and time..."
    uci set system.@system[0].zonename='Europe/Moscow'
    uci set system.@system[0].timezone='MSK-3'
    uci commit system || { log_error "Failed to commit system settings"; exit 1; }

    /etc/init.d/sysntpd restart || log_warning "Failed to restart sysntpd (continuing anyway)"

    log_info "Setting up crontab..."
    # Add scheduled update tasks to cron
    {
        echo "#31 0 * * 1 /usr/bin/wget -qO - https://github.com/Prianik/myVPN/raw/refs/heads/main/z/update.sh | sh"
        echo "#30 0 * * 0 /usr/bin/wget -qO - https://github.com/Prianik/myVPN/raw/refs/heads/main/z/update-dns.sh | sh"
        echo "30 3 * * * /sbin/reboot"
    } >> /etc/crontabs/root

    /etc/init.d/cron restart || log_warning "Failed to restart cron service (continuing anyway)"

    log_info "SYSTEM CONFIGURATION MODE SELECTED"

    # Restore from backup if available, otherwise configure manually
    if [ -f "$BACKUP_FILE" ]; then
        log_info "Backup file detected. Restoring network settings now..."
        restore_config
    else
        local NameSSID0
        local NameSSID1
        local WiFiKey

        # Check if arguments were passed
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

        # Validate inputs
        if [ -z "$NameSSID0" ] || [ -z "$NameSSID1" ] || [ -z "$WiFiKey" ]; then
            log_error "Wi-Fi parameters cannot be empty."
            exit 1
        fi

        log_info "Configuring Wi-Fi..."
        
        # Configure Radio 0 (5GHz typically)
        uci set wireless.@wifi-iface[0].device='radio0'
        uci set wireless.@wifi-iface[0].mode='ap'
        uci set wireless.@wifi-iface[0].disabled=0
        uci set wireless.@wifi-iface[0].ssid="$NameSSID0"
        uci set wireless.@wifi-iface[0].network='lan'
        uci set wireless.@wifi-iface[0].encryption='psk2'
        uci set wireless.@wifi-iface[0].key="$WiFiKey"
        uci set wireless.radio0.disabled=0

        # Configure Radio 1 (2.4GHz typically)
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

        # Configure LAN IP
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

# Mode 5: Factory Reset with Restore
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

# Mode 6: Manual Backup
manual_backup_mode() {
    log_info "MANUAL BACKUP MODE SELECTED"
    backup_config
    log_success "Manual backup completed successfully!"
}

# Mode 7: Manual Restore
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

# Mode 8: Update Installed Packages
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

# Mode 11: Install Zapret-Manager (StressOzz)
install_zapret_manager() {
    log_info "INSTALLING ZAPRET-MANAGER..."
    check_internet
    
    # Если лаунчер уже есть - просто запускаем его
    if [ -f /usr/bin/zms2 ]; then
        log_info "Launcher found, starting..."
        sh /usr/bin/zms2
        return
    fi

    # Если лаунчера нет - устанавливаем зависимости и создаем его
    # Ensure wget with SSL support is available
    if ! opkg list-installed | grep -q wget-ssl; then
        log_info "Installing wget-ssl for secure download..."
        opkg update && opkg install wget-ssl ca-bundle
    fi
    
    log_info "Creating launcher script /usr/bin/zms2..."
    
    # === ПРАВИЛЬНОЕ СОДЕРЖИМОЕ ЛАУНЧЕРА ===
    # Лаунчер должен:
    # 1. Скачать скрипт во временную папку (чтобы не изнашивать флеш-память роутера)
    # 2. Запустить его
    # 3. Удалить временный файл
    cat <<EOF > /usr/bin/zms2
#!/bin/sh
# Temporary file path
TMP_SCRIPT="/tmp/zapret_manager_run.sh"

# Download
echo "Downloading Zapret-Manager..."
if wget -q --no-check-certificate "https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/Zapret-Manager.sh" -O "\$TMP_SCRIPT"; then
    # Execute
    sh "\$TMP_SCRIPT"
    # Cleanup
    rm -f "\$TMP_SCRIPT"
else
    echo "Error: Failed to download script!"
    exit 1
fi
EOF

    chmod +x /usr/bin/zms2
    
    log_info "Launcher created. Starting..."
    sh /usr/bin/zms2
}


# Mode 12: Toggle Web Access (ttyd)
# Enables/Disables ttyd instances for Zapret-Manager and Shell
toggle_web_access() {
    log_info "MANAGING WEB ACCESS (ttyd)..."
    
    # Check if enabled by verifying the launcher script existence
    local is_enabled=0
    if [ -f /usr/bin/zms ] && [ -x /usr/bin/zms ]; then
        is_enabled=1
    fi

    if [ "$is_enabled" -eq 1 ]; then
        # === DISABLE MODE ===
        log_warning "Disabling Web Access..."
        
        # Remove packages
        opkg remove luci-app-ttyd ttyd >/dev/null 2>&1
        
        # Cleanup files and scripts
        rm -f /etc/config/ttyd
        rm -f /usr/bin/zms
        
        # Apply changes
        sync
        
        log_success "Web access removed successfully!"
        read -p "Press Enter to continue..." dummy
    else
        # === ENABLE MODE ===
        log_info "Activating Web Access..."
        check_internet

        # Create launcher script for Zapret-Manager
        echo "Creating launcher script /usr/bin/zms..."
        echo 'sh -c "$(wget -qO- https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/Zapret-Manager.sh)"' > /usr/bin/zms
        chmod +x /usr/bin/zms

        # Install ttyd dependencies
        ttyd_install

        # Configure ttyd using UCI (Explicit Index Method)
        log_info "Configuring ttyd..."

        # 1. Ensure config file exists
        touch /etc/config/ttyd

        # 2. Complete Cleanup: Remove ALL ttyd sections to start fresh
        # This loops until no ttyd sections remain, ensuring [0] and [1] will be fresh
        while uci -q delete ttyd.@ttyd[0]; do :; done

        # 3. Create Zapret-Manager instance (Port 7681) -> Will be index [0]
        uci add ttyd ttyd >/dev/null
        uci set ttyd.@ttyd[0].interface='@lan'
        uci set ttyd.@ttyd[0].command='/bin/sh /usr/bin/zms'
        uci set ttyd.@ttyd[0].port='7681'
        uci set ttyd.@ttyd[0].check_network='0'
        uci set ttyd.@ttyd[0].debug='0'
        # Set client options (title, font size)
        uci set ttyd.@ttyd[0].client_option='title=Zapret-Manager'
        uci add_list ttyd.@ttyd[0].client_option='fontSize=16'

        # 4. Create Standard Shell instance (Port 7682) -> Will be index [1]
        uci add ttyd ttyd >/dev/null
        uci set ttyd.@ttyd[1].interface='@lan'
        uci set ttyd.@ttyd[1].command='/bin/login'
        uci set ttyd.@ttyd[1].port='7682'
        uci set ttyd.@ttyd[1].check_network='0'
        uci set ttyd.@ttyd[1].debug='0'
        uci set ttyd.@ttyd[1].client_option='title=OpenWrt Shell'

        # 5. Commit changes to UCI
        uci commit ttyd
        
        # Restart service to apply changes
        /etc/init.d/ttyd restart >/dev/null 2>&1
        
        # Verify services are running
        sleep 2 # Give it a moment to start
        if pidof ttyd >/dev/null; then
            # Get LAN IP for display
            local lan_ip=$(uci -q get network.lan.ipaddr || echo "ROUTER_IP")
            log_success "Service started successfully!"
            echo ""
            echo -e "${YELLOW}Zapret-Manager:${NC} http://$lan_ip:7681"
            echo -e "${YELLOW}OpenWrt Shell: ${NC} http://$lan_ip:7682"
            echo ""
            read -p "Press Enter to continue..." dummy
        else
            log_error "Error: ttyd service failed to start."
            # Debug info
            echo "Debug: ttyd status:"
            /etc/init.d/ttyd status
            read -p "Press Enter to continue..." dummy
        fi
    fi
}

qr_code() {
   
    if ! opkg list-installed | grep -q qrencode; then
        echo "Устанавливаю qrencode..."
        opkg update
        opkg install qrencode
    fi
    
    clear

    ssid_5g=$(uci get wireless.default_radio0.ssid)
    password_5g=$(uci get wireless.default_radio0.key)
    ssid_2g=$(uci get wireless.default_radio1.ssid)
    password_2g=$(uci get wireless.default_radio1.key)

    echo "=== 5 GHz Network $ssid_5g  Password:$password_5g ==="
    qrencode -t ansiutf8 "WIFI:S:$ssid_5g;T:WPA2;P:$password_5g;;"
    echo -e "\n\n\n"
    echo "=== 2.4 GHz Network  $ssid_2g  Password:$password_2g ==="
    qrencode -t ansiutf8 "WIFI:S:$ssid_2g;T:WPA2;P:$password_2g;;"
}


# ==============================================================================
# Main Menu and Execution
# ==============================================================================

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
    echo "5) Factory reset with restore (backup -> reset -> update -> restore)"
    echo "6) Manual backup"
    echo "7) Restore network settings from backup"
    echo "8) Update installed packages"
    echo "9) Updating/Installing update_dns_proxy"
    echo "10) Updating/Installing ttyd"
    echo "11) Install Zapret-Manager (StressOzz)"
    echo "12) Toggle Web Access (Browser Terminal)"
    echo "13) Output WiFi-code)"
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
    echo "- Mode 9: Updating/Installing https-dns-proxy"
    echo "- Mode 10: Updating/Installing ttyd"
    echo "- Mode 11: Run external Zapret-Manager installer"
    echo "- Mode 12: Enable/Disable Web Terminal (ttyd) with Zapret-Manager"
    echo "- Mode 13: WiFi-code"
    echo ""
}

main() {
    show_menu

    read -rp "Enter your choice (1-13): " choice

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
        9)
            update_dns_proxy
            ;;
        10)
            ttyd_install
            ;;
        11)
            install_zapret_manager
            ;;
        12)
            toggle_web_access
            ;;
        13)
            qr_code
            ;;
        *)
            log_error "Invalid choice. Please enter 1-12."
            exit 1
            ;;
    esac
}

# Execute main function with all arguments passed to script
main "$@"
