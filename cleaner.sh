#!/bin/bash
# cleaner.sh
#
# Этот скрипт удаляет все созданные ресурсы:
# 1. Удаляет домены (виртуальные машины) libvirt.
# 2. Удаляет виртуальные диски и cloud-init ISO, созданные через Terraform.
# 3. Удаляет пул libvirt "gitea_pool".
# 4. Очищает DHCP-лизы для сети по умолчанию.
# 5. Удаляет старые записи в файле known_hosts для виртуальных машин.
# 6. (Опционально) Удаляет файлы состояния Terraform.
#
# Рекомендуется запускать этот скрипт от root (или через sudo).
#
# Логирование ведется в файле cleaner.log.

LOGFILE="cleaner.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

if [ "$EUID" -ne 0 ]; then
    log "WARNING: Рекомендуется запускать этот скрипт от root или через sudo."
fi

log "=== Начало очистки через cleaner.sh ==="

# 1. Удаление виртуальных машин
log "Удаляю домены (виртуальные машины) gitea-node-1 и gitea-node-2..."
for domain in gitea-node-1 gitea-node-2; do
    if virsh dominfo "$domain" &>/dev/null; then
        sudo virsh destroy "$domain" 2>/dev/null
        sudo virsh undefine "$domain" --remove-all-storage 2>/dev/null
        log "Домен $domain удалён."
    else
        log "Домен $domain не найден."
    fi
done

# 2. Удаление виртуальных дисков и cloud-init ISO из пула
log "Удаляю виртуальные диски и cloud-init ISO из пула gitea_pool..."
if virsh pool-info gitea_pool &>/dev/null; then
    sudo virsh pool-destroy gitea_pool 2>/dev/null
    sudo virsh pool-undefine gitea_pool 2>/dev/null
    log "Пул gitea_pool удалён."
else
    log "Пул gitea_pool не найден."
fi
rm -rf /home/shom/virsh_HDD/gitea_pool

# 3. Очистка DHCP-лизов для сети по умолчанию
#if [ -f /var/lib/libvirt/dnsmasq/default.leases ]; then
#   log "Удаляю старые DHCP-лизы из /var/lib/libvirt/dnsmasq/default.leases"
#    sudo rm -f /var/lib/libvirt/dnsmasq/default.leases
#    sudo virsh net-destroy default && sudo virsh net-start default
#else
#    log "Файл DHCP-лизов не найден."
#fi

# 3. Очистка DHCP-лизов для сети по умолчанию
log "Очищаю DHCP-лизы для IP 192.168.122.101 и 192.168.122.102..."
if [ -f /var/lib/libvirt/dnsmasq/virbr0.status ]; then
    # Создать резервную копию
    cp /var/lib/libvirt/dnsmasq/virbr0.status /var/lib/libvirt/dnsmasq/virbr0.status.bak
    
    # Вариант с jq (если установлен)
    if command -v jq &> /dev/null; then
        jq '[.[] | select(.["ip-address"] != "192.168.122.101" and .["ip-address"] != "192.168.122.102")]' /var/lib/libvirt/dnsmasq/virbr0.status.bak > /var/lib/libvirt/dnsmasq/virbr0.status
    else
        # Простой вариант - просто очистить все
        echo "[]" > /var/lib/libvirt/dnsmasq/virbr0.status
    fi
    
    # Перезапустить сеть
    virsh net-destroy default && virsh net-start default
    log "DHCP-лизы для указанных IP-адресов успешно удалены."
else
    log "Файл DHCP-лизов virbr0.status не найден."
fi

# 4. Удаление старых записей в known_hosts
log "Удаляю старые записи в known_hosts для IP 192.168.122.101 и 192.168.122.102..."
sudo ssh-keygen -R 192.168.122.101 2>/dev/null
sudo ssh-keygen -R 192.168.122.102 2>/dev/null
# Если known_hosts находится в другом месте (например, /root/.ssh/known_hosts), можно также выполнить:
# sudo ssh-keygen -R 192.168.122.101 -f /root/.ssh/known_hosts
# sudo ssh-keygen -R 192.168.122.102 -f /root/.ssh/known_hosts

# 5. (Опционально) Удаление файлов состояния Terraform
read -p "Удалить файлы состояния Terraform? [y/N]: " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
    log "Удаляю файлы состояния Terraform..."
    rm -f terraform/terraform.tfstate*
    log "Файлы состояния Terraform удалены."
fi

log "=== Очистка завершена успешно ==="

exit 0

