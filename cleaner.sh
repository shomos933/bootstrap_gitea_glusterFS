#!/bin/bash
# cleaner.sh
#
# Этот скрипт удаляет все созданные ресурсы:
# 1. Удаляет домены (виртуальные машины) libvirt.
# 2. Удаляет виртуальные диски и cloud-init ISO, созданные через Terraform.
# 3. Удаляет пул libvirt "gitea_pool".
# 4. (Опционально) Удаляет файлы состояния Terraform.
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
# Сначала остановим пул, затем удалим его
if virsh pool-info gitea_pool &>/dev/null; then
    sudo virsh pool-destroy gitea_pool 2>/dev/null
    sudo virsh pool-undefine gitea_pool 2>/dev/null
    log "Пул gitea_pool удалён."
else
    log "Пул gitea_pool не найден."
fi

# 3. (Опционально) Удаление файлов состояния Terraform
read -p "Удалить файлы состояния Terraform? [y/N]: " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
    log "Удаляю файлы состояния Terraform..."
    rm -f terraform/terraform.tfstate*
    log "Файлы состояния Terraform удалены."
fi

log "=== Очистка завершена успешно ==="

exit 0

