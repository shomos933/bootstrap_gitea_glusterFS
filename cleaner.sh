#!/bin/bash
# cleaner.sh — менюный скрипт для удаления VM, пулов и сетей libvirt
#
# Пункты меню:
#   1) Удалить Kubernetes-кластер
#      • ВМ: k8s-master, k8s-worker-1, k8s-worker-2
#      • Пул: k8s_pool
#      • Сеть: k8s-net
#   2) Удалить Gitea+NFS
#      • ВМ: gitea-node-1, gitea-node-2, nfs-node
#      • Пулы: gitea_pool, nfs_pool
#      • Сеть: default
#   3) Удалить ВСЕ ресурсы (оба набора и обе сети)
#
# После выбора нужно ввести 'Yes' для подтверждения.
# Рекомендуется запускать от root или через sudo.

LOGFILE="cleaner.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

# Очистим старый лог
> "$LOGFILE"

# Меню выбора
cat <<EOF
=============================
       CLEANER MENU
=============================
1) Удалить Kubernetes-кластер
2) Удалить Gitea+NFS
3) Удалить ВСЕ ресурсы
=============================
EOF

read -rp "Выберите пункт (1/2/3): " choice

# Подготовка списков по выбору
case "$choice" in
  1)
    DESC="Kubernetes-кластер"
    DOMAINS=(k8s-master k8s-worker-1 k8s-worker-2)
    POOLS=(k8s_pool)
    NETWORKS=(k8s-net)
    STATE_DIRS=("terraform-k8s-cluster")
    ;;
  2)
    DESC="Gitea+NFS"
    DOMAINS=(gitea-node-1 gitea-node-2 nfs-node)
    POOLS=(gitea_pool nfs_pool)
    NETWORKS=(default)
    STATE_DIRS=("terraform")
    ;;
  3)
    DESC="Все ресурсы"
    DOMAINS=(k8s-master k8s-worker-1 k8s-worker-2 \
             gitea-node-1 gitea-node-2 nfs-node)
    POOLS=(k8s_pool gitea_pool nfs_pool)
    NETWORKS=(k8s-net default)
    STATE_DIRS=("terraform-k8s-cluster" "terraform")
    ;;
  *)
    echo "Неверный выбор, выходим."
    exit 1
    ;;
esac

# Подтверждение
echo
echo "Выбран пункт: $choice — удаляем: $DESC"
echo " ВМ:       ${DOMAINS[*]}"
echo " Пулы:     ${POOLS[*]}"
echo " Сети:     ${NETWORKS[*]}"
echo " TF-state: ${STATE_DIRS[*]}"
read -rp "Для продолжения введите 'Yes' или 'No' чтобы прервать: " CONFIRM
if [[ "$CONFIRM" != "Yes" ]]; then
    echo "Операция отменена."
    exit 1
fi
echo

log "=== Начинаем очистку: $DESC ==="
if [ "$EUID" -ne 0 ]; then
    log "WARNING: рекомендуется запускать от root или через sudo."
fi

# 1) Удаляем ВМ
for dom in "${DOMAINS[@]}"; do
    if virsh dominfo "$dom" &>/dev/null; then
        log "Убиваю и undefine VM: $dom"
        virsh destroy "$dom"       &>/dev/null || true
        virsh undefine "$dom" --remove-all-storage &>/dev/null || true
        log "  → $dom удалён"
    else
        log "  → $dom не найден"
    fi
done

# 2) Удаляем пулы и их каталоги
for pool in "${POOLS[@]}"; do
    if virsh pool-info "$pool" &>/dev/null; then
        log "Останавливаю и undefine пул: $pool"
        virsh pool-destroy "$pool"  &>/dev/null || true
        virsh pool-undefine "$pool" &>/dev/null || true
        log "  → пул $pool удалён"
    else
        log "  → пул $pool не найден"
    fi

    # Определяем директорию пула
    if [ "$pool" = "nfs_pool" ]; then
        DIR="/var/lib/libvirt/nfs_pool"
    else
        DIR=$(virsh pool-dumpxml "$pool" 2>/dev/null \
              | sed -n 's:.*<target><path>\(.*\)</path>.*:\1:p')
        [ -z "$DIR" ] && DIR="/home/shom/virsh_HDD/$pool"
    fi

    if [ -d "$DIR" ]; then
        rm -rf "$DIR"
        log "  → удалена папка пула: $DIR"
    fi
done

# 3) Удаляем сети (и все лизы/конфиги dnsmasq)
for net in "${NETWORKS[@]}"; do
    if virsh net-info "$net" &>/dev/null; then
        log "Останавливаю и undefine сеть: $net"
        virsh net-destroy "$net"  &>/dev/null || true
        virsh net-undefine "$net" &>/dev/null || true
        log "  → сеть $net удалена"
    else
        log "  → сеть $net не найдена"
    fi
done

# 4) Удаляем файлы Terraform state
for dir in "${STATE_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        rm -f "$dir"/terraform.tfstate* 2>/dev/null
        log "  → state-файлы удалены в $dir"
    fi
done

log "=== Очистка завершена ==="
exit 0

