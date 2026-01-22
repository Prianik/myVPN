#!/bin/sh

# URL для загрузки пакетов Zapret и DNS списков
ZAPRET_BASE_URL="https://github.com/Prianik/myVPN/raw/refs/heads/main/z"
ZAPRET_VER_FILE="ZAPRET_VER.txt"
DNS_FILES_URL="https://raw.githubusercontent.com/Prianik/myVPN/refs/heads/main"

# Резервное копирование конфигурации
BACKUP_DIR="/root"
BACKUP_FILE="$BACKUP_DIR/config_backup.tar.gz"

# Параметры повторных попыток загрузки для надежности
MAX_RETRIES=3
RETRY_SLEEP=2

# ==============================================================================
# Цветовые коды для вывода
# ==============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ==============================================================================
# Функции логирования
# ==============================================================================

# Информационные сообщения (синий)
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Сообщения об успехе (зеленый)
log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Предупреждения (желтый)
log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Сообщения об ошибках (красный)
log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# ==============================================================================
# Обработка ошибок
# ==============================================================================

# Функция для обработки ошибок, перехваченных командой 'trap'
# Аргументы:
#   $1: Номер строки, где произошла ошибка
#   $2: Код завершения команды, которая завершилась неудачей
handle_error() {
    log_error "Скрипт завершился с ошибкой на строке $1 с кодом $2"
    exit $2
}

# Настройка trap для вызова handle_error при любой ошибке выполнения команд
# Примечание: 'ERR' trap не является стандартным POSIX sh, но работает во многих оболочках.
trap 'handle_error $LINENO $?' ERR

# ==============================================================================
# Вспомогательные функции
# ==============================================================================

# Проверка активного подключения к интернету с помощью ping github.com
check_internet() {
    if ! ping -c 1 -W 3 github.com >/dev/null 2>&1; then
        log_error "Нет подключения к интернету. Пожалуйста, проверьте вашу сеть."
        exit 1
    fi
}

# Загрузка файла с автоматическими повторными попытками
# Аргументы:
#   $1: URL для загрузки
#   $2: Имя выходного файла
download_file() {
    local url=$1
    local filename=$2
    local retry_count=0

    while [ $retry_count -lt $MAX_RETRIES ]; do
        if wget --show-progress -q "$url" -O "$filename"; then
            return 0
        fi
        retry_count=$((retry_count + 1))
        log_warning "Ошибка загрузки, повторная попытка $retry_count/$MAX_RETRIES..."
        sleep $RETRY_SLEEP
    done

    log_error "Не удалось загрузить: $url"
    return 1
}

# Ручное копирование конфигурационных файлов из источника в назначение
# Аргументы:
#   $1: Исходная директория
#   $2: Целевая директория
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
# Функции резервного копирования и восстановления
# ==============================================================================

# Создание резервной копии критических сетевых и беспроводных конфигураций
backup_config() {
    log_info "Создание резервной копии сетевой конфигурации..."

    mkdir -p "$BACKUP_DIR"
    local config_files="/etc/config/network /etc/config/wireless"

    # Попытка создать архив tar
    if ! tar -czf "$BACKUP_FILE" $config_files 2>/dev/null; then
        log_warning "Не удалось создать архив резервной копии, копируем файлы вручную..."
        copy_config_files "/etc/config" "$BACKUP_DIR"
    fi

    # Проверка успешности резервного копирования
    if [ -f "$BACKUP_FILE" ] || { [ -f "$BACKUP_DIR/network" ] && [ -f "$BACKUP_DIR/wireless" ]; }; then
        log_success "Резервная копия конфигурации создана в $BACKUP_FILE"
        echo "Пожалуйста, загрузите файл резервной копии через SCP!"
    else
        log_error "Резервное копирование не удалось. Файлы резервных копий не найдены."
        exit 1
    fi
}

# Восстановление сетевой конфигурации из ранее созданной резервной копии
restore_config() {
    log_info "Восстановление сетевой конфигурации из резервной копии..."

    if [ ! -f "$BACKUP_FILE" ]; then
        log_warning "Архив резервной копии $BACKUP_FILE не найден. Пробуем ручное восстановление..."
        if [ -f "$BACKUP_DIR/network" ] && [ -f "$BACKUP_DIR/wireless" ]; then
            copy_config_files "$BACKUP_DIR" "/etc/config"
            log_info "Ручное восстановление завершено."
        else
            log_error "Не найдены файлы для восстановления из резервной копии."
            return 1
        fi
    else
        # Извлечение архива в корневую директорию
        if ! tar -xzf "$BACKUP_FILE" -C / 2>/dev/null; then
            log_warning "Не удалось извлечь архив резервной копии, пробуем ручное восстановление..."
            copy_config_files "$BACKUP_DIR" "/etc/config"
        fi
    fi

    # Перезапуск сетевых служб для применения изменений
    /etc/init.d/network restart
    /etc/init.d/firewall restart
    /etc/init.d/dnsmasq restart

    log_success "Конфигурация успешно восстановлена."
    rm -f "$BACKUP_FILE"
    log_info "Файл резервной копии удален после успешного восстановления."
}

# Выполнение сброса к заводским настройкам с сохранением текущей конфигурации через резервное копирование/восстановление
reset_to_factory() {
    log_info "Сброс к заводским настройкам..."
    backup_config

    log_warning "ЭТО СБРОСИТ ВСЕ НАСТРОЙКИ К ЗАВОДСКИМ ЗНАЧЕНИЯМ ПО УМОЛЧАНИЮ!"
    log_warning "Все текущие конфигурации будут потеряны!"

    read -p "Вы уверены, что хотите продолжить? (y/N): " confirm
    case "$confirm" in
        y|Y|yes|YES)
            log_info "Выполнение сброса к заводским настройкам..."
            firstboot -y && reboot
            ;;
        *)
            log_info "Сброс к заводским настройкам отменен."
            return 1
            ;;
    esac
}

# ==============================================================================
# Логика установки и обновления
# ==============================================================================

# Режим 1: Полная автоматическая установка
# Объединяет обновление и настройку системы
full_auto_install_mode() {
    log_info "ВЫБРАН РЕЖИМ ПОЛНОЙ АВТОМАТИЧЕСКОЙ УСТАНОВКИ"

    # Обработка необязательных параметров WiFi, переданных в качестве аргументов
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

    log_success "Полная автоматическая установка успешно завершена!"
}

# Режим 2: Полное автоматическое обновление
# Обновляет системные пакеты, удаляет конфликтующие и устанавливает/обновляет инструменты
update_mode() {
    log_info "ВЫБРАН РЕЖИМ ПОЛНОГО АВТОМАТИЧЕСКОГО ОБНОВЛЕНИЯ"
    check_internet

    log_info "Обновление списков пакетов..."
    if ! opkg update; then
        log_error "Не удалось обновить списки пакетов. Проверьте подключение к интернету или URL репозиториев."
        exit 1
    fi

    # Установка основных инструментов поддержки SSL
    for pkg in ca-certificates wget-ssl qrencode ttyd unzip ca-bundle; do
        if ! opkg list-installed | grep -q "^$pkg"; then
            log_info "Установка $pkg..."
            opkg install "$pkg" || { log_error "Не удалось установить $pkg"; exit 1; }
        else
            log_info "Пакет $pkg уже установлен..."
        fi
    done

    # Удаление конфликтующих пакетов (например, nfqws-keenetic)
    log_info "Удаление пакетов nfqws-keenetic..."
    if opkg list-installed | grep -q nfqws-keenetic; then
        opkg remove nfqws-keenetic* || log_warning "Не удалось удалить пакеты nfqws-keenetic (продолжаем в любом случае)"
    else
        log_info "Пакеты nfqws-keenetic не найдены. Пропускаем удаление."
    fi

    # Обновление всех обновляемых пакетов
    log_info "Обновление установленных пакетов..."
    upgradable_pkgs=$(opkg list-upgradable | awk '{print $1}')
    if [ -n "$upgradable_pkgs" ]; then
        echo "$upgradable_pkgs" | xargs -r opkg upgrade
    else
        log_info "Нет пакетов для обновления."
    fi

    # Обновление специфических инструментов
    update_dns_proxy
#   toggle_web_access_mini
#    install_zapret_manager

    # Перезапуск RPC демона
    service rpcd restart || log_warning "Не удалось перезапустить rpcd (продолжаем в любом случае)"
    log_success "Полное автоматическое обновление успешно завершено!"
}

# Режим 10: Установка/Обновление ttyd (Веб-терминал)
ttyd_install() {
    log_info "Установка ttyd..."
#
    if ! opkg list-installed | grep -q ttyd; then
        log_info "Установка ttyd..."
        opkg update
        opkg install ttyd luci-app-ttyd || { log_error "Не удалось установить ttyd"; exit 1; }
    fi
}

# Режим 9: Обновление/Установка https-dns-proxy
update_dns_proxy() {
    log_info "Обновление/Установка https-dns-proxy..."
    if opkg list-installed | grep -q https-dns-proxy; then
        log_info "https-dns-proxy установлен. Выполняем обновление..."
        opkg install --force-reinstall https-dns-proxy luci-app-https-dns-proxy || {
            log_error "Не удалось обновить https-dns-proxy"
            exit 1
        }
    else
        log_info "https-dns-proxy не установлен. Выполняем установку..."
        opkg install https-dns-proxy luci-app-https-dns-proxy || {
            log_error "Не удалось установить https-dns-proxy"
            exit 1
        }
    fi
}

# ==============================================================================
# Функции настройки системы
# ==============================================================================

# Режим 3: Настройка параметров системы (Часовой пояс, Cron, WiFi, Сеть)
system_config_mode() {
    log_info "Настройка часового пояса и времени..."
    uci set system.@system[0].zonename='Europe/Moscow'
    uci set system.@system[0].timezone='MSK-3'
    uci commit system || { log_error "Не удалось сохранить настройки системы"; exit 1; }

    /etc/init.d/sysntpd restart || log_warning "Не удалось перезапустить sysntpd (продолжаем в любом случае)"

    log_info "Настройка crontab..."
    # Добавление запланированных задач обновления в cron
    {
        echo "#31 0 * * 1 /usr/bin/wget -qO - https://github.com/Prianik/myVPN/raw/refs/heads/main/z/update.sh | sh"
        echo "#30 0 * * 0 /usr/bin/wget -qO - https://github.com/Prianik/myVPN/raw/refs/heads/main/z/update-dns.sh | sh"
        echo "30 3 * * * /sbin/reboot"
    } >> /etc/crontabs/root

    /etc/init.d/cron restart || log_warning "Не удалось перезапустить службу cron (продолжаем в любом случае)"

    log_info "ВЫБРАН РЕЖИМ НАСТРОЙКИ СИСТЕМЫ"

    # Восстановление из резервной копии, если доступно, иначе ручная настройка
    if [ -f "$BACKUP_FILE" ]; then
        log_info "Обнаружен файл резервной копии. Восстанавливаем сетевые настройки..."
        restore_config
    else
        local NameSSID0
        local NameSSID1
        local WiFiKey

        # Проверка, переданы ли аргументы
        if [ $# -eq 3 ]; then
            NameSSID0=$1
            NameSSID1=$2
            WiFiKey=$3
        else
            log_info "Параметры Wi-Fi не предоставлены. Запрашиваем ввод..."
            read -p "Введите NameSSID для WiFi5: " NameSSID0
            read -p "Введите NameSSID для WiFi2.4: " NameSSID1
            read -s -p "Введите пароль Wi-Fi: " WiFiKey
            echo
        fi

        # Проверка введенных данных
        if [ -z "$NameSSID0" ] || [ -z "$NameSSID1" ] || [ -z "$WiFiKey" ]; then
            log_error "Параметры Wi-Fi не могут быть пустыми."
            exit 1
        fi

        log_info "Настройка Wi-Fi..."
        
        # Настройка Radio 0 (обычно 5GHz)
        uci set wireless.@wifi-iface[0].device='radio0'
        uci set wireless.@wifi-iface[0].mode='ap'
        uci set wireless.@wifi-iface[0].disabled=0
        uci set wireless.@wifi-iface[0].ssid="$NameSSID0"
        uci set wireless.@wifi-iface[0].network='lan'
        uci set wireless.@wifi-iface[0].encryption='psk2'
        uci set wireless.@wifi-iface[0].key="$WiFiKey"
        uci set wireless.radio0.disabled=0

        # Настройка Radio 1 (обычно 2.4GHz)
        uci set wireless.@wifi-iface[1].device='radio1'
        uci set wireless.@wifi-iface[1].mode='ap'
        uci set wireless.@wifi-iface[1].disabled=0
        uci set wireless.@wifi-iface[1].ssid="$NameSSID1"
        uci set wireless.@wifi-iface[1].network='lan'
        uci set wireless.@wifi-iface[1].encryption='psk2'
        uci set wireless.@wifi-iface[1].key="$WiFiKey"
        uci set wireless.radio1.disabled=0

        uci commit wireless || { log_error "Не удалось сохранить настройки Wi-Fi"; exit 1; }
        log_info "Настройки Wi-Fi применены"

        qr_code

        # Настройка LAN IP
        log_info "Установка LAN IP на 172.16.1.1..."
        uci set network.lan.ipaddr='172.16.1.1'
        uci commit network || { log_error "Не удалось сохранить сетевые настройки"; exit 1; }

        if ! /etc/init.d/network restart; then
            log_warning "Не удалось перезапустить сеть (продолжаем в любом случае)"
        fi

        log_info "Локальный IP адрес сети изменен на 172.16.1.1"
    fi

    # Очистка временных файлов
 #   rm -f ./*

    log_success "Настройка системы успешно завершена!"
}

# Режим 5: Сброс к заводским настройкам с восстановлением
factory_reset_with_restore_mode() {
    log_info "ВЫБРАН РЕЖИМ СБРОСА К ЗАВОДСКИМ НАСТРОЙКАМ С ВОССТАНОВЛЕНИЕМ"
    backup_config

    echo "Файл резервной копии сохранен в $BACKUP_FILE."
    echo "Пожалуйста, загрузите его (например, с помощью scp) перед продолжением сброса к заводским настройкам."

    read -p "Нажмите Enter для продолжения сброса к заводским настройкам или Ctrl+C для отмены..."
    if reset_to_factory; then
        log_info "Ожидание перезагрузки системы после сброса к заводским настройкам..."
        log_info "После перезагрузки, пожалуйста, запустите этот скрипт снова для восстановления вашей конфигурации."
        exit 0
    else
        log_info "Сброс к заводским настройкам отменен. Продолжаем с обновлением и восстановлением..."
    fi

    update_mode
    restore_config

    log_success "Сброс к заводским настройкам с восстановлением успешно завершен!"
}

# Режим 6: Ручное резервное копирование
manual_backup_mode() {
    log_info "ВЫБРАН РЕЖИМ РУЧНОГО РЕЗЕРВНОГО КОПИРОВАНИЯ"
    backup_config
    log_success "Ручное резервное копирование успешно завершено!"
}

# Режим 7: Ручное восстановление
manual_restore_mode() {
    log_info "ВЫБРАН РЕЖИМ РУЧНОГО ВОССТАНОВЛЕНИЯ"

    if [ -f "$BACKUP_FILE" ]; then
        log_info "Обнаружен файл резервной копии. Восстанавливаем сетевые настройки..."
        restore_config
    else
        log_error "Файл резервной копии $BACKUP_FILE не найден. Невозможно восстановить."
        exit 1
    fi
}

# Режим 8: Обновление установленных пакетов
update_installed_packages() {
    log_info "Обновление списков пакетов..."
    if ! opkg update; then
        log_error "Не удалось обновить списки пакетов."
        exit 1
    fi

    log_info "Обновление установленных пакетов..."
    upgradable_pkgs=$(opkg list-upgradable | cut -f 1 -d ' ')
    if [ -n "$upgradable_pkgs" ]; then
        echo "$upgradable_pkgs" | xargs -r opkg upgrade
        log_success "Обновление пакетов завершено."
    else
        log_info "Нет пакетов для обновления."
    fi
}

# Режим 11: Установка Zapret-Manager (StressOzz)
install_zapret_manager() {
    log_info "УСТАНОВКА ZAPRET-MANAGER..."
    check_internet
    
    # Если лаунчер уже есть - просто запускаем его
    if [ -f /usr/bin/zms2 ]; then
        log_info "Лаунчер найден, запускаем..."
        sh /usr/bin/zms2
        return
    fi

    # Если лаунчера нет - устанавливаем зависимости и создаем его
    # Убедимся, что wget с поддержкой SSL доступен
    for pkg in wget-ssl ca-bundle; do
        if ! opkg list-installed | grep -q "^$pkg"; then
            log_info "Установка $pkg..."
            opkg install "$pkg" || { log_error "Не удалось установить $pkg"; exit 1; }
        fi
    done
    
    log_info "Создание скрипта-лаунчера /usr/bin/zms2..."
    
    # === ПРАВИЛЬНОЕ СОДЕРЖИМОЕ ЛАУНЧЕРА ===
    # Лаунчер должен:
    # 1. Скачать скрипт во временную папку (чтобы не изнашивать флеш-память роутера)
    # 2. Запустить его
    # 3. Удалить временный файл
    cat <<EOF > /usr/bin/zms2
#!/bin/sh
# Путь к временному файлу
TMP_SCRIPT="/tmp/zapret_manager_run.sh"

# Загрузка
echo "Загрузка Zapret-Manager..."
if wget -q --no-check-certificate "https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/Zapret-Manager.sh" -O "\$TMP_SCRIPT"; then
    # Выполнение
    sh "\$TMP_SCRIPT"
    # Очистка
    rm -f "\$TMP_SCRIPT"
else
    echo "Ошибка: Не удалось загрузить скрипт!"
    exit 1
fi
EOF

    chmod +x /usr/bin/zms2
    
    log_info "Лаунчер создан. Запускаем..."
    sh /usr/bin/zms2
}


# Режим 12: Переключение веб-доступа (ttyd)
# Включает/выключает экземпляры ttyd для Zapret-Manager и оболочки


toggle_web_access_mini() {
    log_info "УПРАВЛЕНИЕ ВЕБ-ДОСТУПОМ (ttyd)..."

                # Создание скрипта-лаунчера для Zapret-Manager
        echo "Создание скрипта-лаунчера /usr/bin/zms..."
        echo 'sh -c "$(wget -qO- https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/Zapret-Manager.sh)"' > /usr/bin/zms
        chmod +x /usr/bin/zms

        log_info "Настройка ttyd..."
        ttyd_install
        
        # 1. Убедиться, что конфигурационный файл существует
        touch /etc/config/ttyd
        while uci -q delete ttyd.@ttyd[0]; do :; done
        uci add ttyd ttyd >/dev/null
        uci set ttyd.@ttyd[0].interface='@lan'
        uci set ttyd.@ttyd[0].command='/bin/sh /usr/bin/zms'
        uci set ttyd.@ttyd[0].port='7681'
        uci set ttyd.@ttyd[0].check_network='0'
        uci set ttyd.@ttyd[0].debug='0'
        # Установка параметров клиента (заголовок, размер шрифта)
        uci set ttyd.@ttyd[0].client_option='title=Zapret-Manager'
        uci add_list ttyd.@ttyd[0].client_option='fontSize=16'
        uci commit ttyd
        /etc/init.d/ttyd restart >/dev/null 2>&1

}


qr_code() {
   
    if ! opkg list-installed | grep -q qrencode; then
        echo "Установка qrencode..."
        opkg update
        opkg install qrencode
    fi
    
    clear

    ssid_5g=$(uci get wireless.default_radio0.ssid)
    password_5g=$(uci get wireless.default_radio0.key)
    ssid_2g=$(uci get wireless.default_radio1.ssid)
    password_2g=$(uci get wireless.default_radio1.key)

    echo "=== 5 GHz Сеть $ssid_5g  Пароль:$password_5g ==="
    qrencode -t ansiutf8 "WIFI:S:$ssid_5g;T:WPA2;P:$password_5g;;"
    echo -e "\n\n\n"
    echo "=== 2.4 GHz Сеть  $ssid_2g  Пароль:$password_2g ==="
    qrencode -t ansiutf8 "WIFI:S:$ssid_2g;T:WPA2;P:$password_2g;;"
}


# ==============================================================================
# Главное меню и выполнение
# ==============================================================================

show_menu() {
    echo ""
    echo "=========================================="
    echo " Скрипт настройки OpenWRT"
    echo "=========================================="
    echo ""
    echo "Выберите режим:"
    echo "1) Полная автоматическая УСТАНОВКА (обновление + настройка)"
    echo "2) Полное автоматическое ОБНОВЛЕНИЕ (удаление keenetic, обновление пакетов, ZAPRET, DNS, https-dns-proxy)"
    echo "3) Настройка системы (СЕТЬ, WiFi, crontab)"

    echo "5) Сброс к заводским настройкам с восстановлением (резервная копия -> сброс -> обновление -> восстановление)"
    echo "6) Ручное резервное копирование"
    echo "7) Восстановление сетевых настроек из резервной копии"
    echo "8) Обновление установленных пакетов"
    echo "9) Обновление/установка https-dns-proxy"
    echo "10) Обновление/установка ttyd"
    echo "11) Установка-Запуск Zapret-Manager (StressOzz)"
    echo "12) Переключение веб-доступа (браузерный терминал)"
    echo "13) Вывод QR-кода WiFi"
    echo ""
}

main() {
    show_menu

    read -rp "Введите ваш выбор (1-13): " choice

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
            log_error "Неверный выбор. Пожалуйста, введите 1-13."
            exit 1
            ;;
    esac
}

# Выполнение основной функции со всеми аргументами, переданными скрипту
main "$@"