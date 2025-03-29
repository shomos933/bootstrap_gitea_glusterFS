#!/bin/bash
# master.sh
#
# Этот скрипт выполняет полное развертывание инфраструктуры:
# 1. Устанавливает необходимые пакеты (для Debian/Ubuntu и RHEL/CentOS).
# 2. Запускает Terraform для создания виртуальных машин.
# 3. Если Terraform завершился успешно, обновляет known_hosts.
# 4. Запускает Ansible для дальнейшей настройки серверов.
#
# Логирование ведется в файле master.log в корне проекта.

LOGFILE="master.log"
TERRAFORM_VERSION="1.11.0"

# Функция логирования с меткой времени
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

log "=== Начало развертывания через master.sh ==="

# Функция установки необходимых пакетов в зависимости от ОС
install_packages() {
    if [ -f /etc/debian_version ]; then
        log "Debian/Ubuntu-система обнаружена. Устанавливаю пакеты..."
        sudo apt update
        sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils terraform ansible cloud-utils jq git
    elif [ -f /etc/redhat-release ]; then
        log "RHEL/CentOS-система обнаружена. Устанавливаю пакеты..."
        # Установка базовых пакетов
        sudo dnf install -y qemu-kvm libvirt libvirt-client virt-install jq git
        # Установка EPEL, если еще не установлен
        if ! rpm -q epel-release &>/dev/null; then
            log "EPEL не найден. Устанавливаю EPEL..."
            sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
        fi
        # Установка Ansible Core и cloud-utils-growpart
        sudo dnf install -y ansible-core cloud-utils-growpart
        # Проверка наличия terraform (если отсутствует – скачать и установить вручную)
        if ! command -v terraform &>/dev/null; then
            log "Terraform не найден. Скачиваю и устанавливаю Terraform..."
            TERRAFORM_VERSION="1.5.0"  # укажите нужную версию
            wget https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip
            unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip
            sudo mv terraform /usr/local/bin/
            rm terraform_${TERRAFORM_VERSION}_linux_amd64.zip
        fi
    else
        log "Неизвестная ОС. Установку пакетов необходимо выполнить вручную."
        exit 1
    fi
    log "Установка пакетов завершена."
}

install_packages

# Убеждаемся, что libvirtd запущен и пользователь входит в группу libvirt
log "Запускаю libvirtd..."
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt $(whoami)
newgrp libvirt

# Запуск Terraform
log "Запуск Terraform..."
cd terraform || { log "Не удалось перейти в каталог terraform"; exit 1; }

log "Инициализация Terraform..."
terraform init | tee -a "../$LOGFILE"
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    log "Ошибка: terraform init завершился с ошибкой."
    exit 1
fi

log "Планирование развертывания Terraform..."
terraform plan | tee -a "../$LOGFILE"
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    log "Ошибка: terraform plan завершился с ошибкой."
    exit 1
fi

log "Применение конфигурации Terraform..."
terraform apply -auto-approve | tee -a "../$LOGFILE"
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    log "Ошибка: terraform apply завершился с ошибкой."
    exit 1
fi
cd .. || exit 1
log "Terraform успешно завершился."

# Обновление known_hosts для созданных серверов
log "Обновление known_hosts..."
# Здесь предполагается, что статические IP совпадают с теми, что указаны в inventory.ini (например, 192.168.122.101 и 192.168.122.102)
for ip in 192.168.122.101 192.168.122.102; do
  ssh-keyscan -H "$ip" >> ~/.ssh/known_hosts
done

# Запуск Ansible playbook
log "Запуск Ansible playbook..."
cd ansible || { log "Не удалось перейти в каталог ansible"; exit 1; }
ansible-playbook -i inventory.ini playbook.yml | tee -a "../$LOGFILE"
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    log "Ошибка: Ansible playbook завершился с ошибкой."
    exit 1
fi
cd .. || exit 1
log "Ansible playbook успешно выполнен."
log "=== Развертывание завершено успешно ==="

exit 0

