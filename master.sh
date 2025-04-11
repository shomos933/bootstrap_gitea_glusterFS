#!/bin/bash
# master.sh
#
# Этот скрипт выполняет полное развертывание инфраструктуры:
# 1. Устанавливает необходимые пакеты.
# 2. (Опционально) Подготавливает образ ОС, если его нет.
# 3. Проверяет наличие пользователя "shom" и, если его нет, создаёт его;
#    также настраивает домашний каталог /home/shom и каталог для образов /home/shom/OS_images.
# 4. Проверяет и создает каталог для пула libvirt (/home/shom/virsh_HDD) с нужными правами,
#    устанавливает права на родительские каталоги и задаёт правильный SELinux-контекст.
# 5. Добавляет пользователя "shom" в группу libvirt.
# 6. Запускает Terraform для создания виртуальных машин.
# 7. Обновляет known_hosts для созданных серверов.
# 8. Запускает Ansible для дальнейшей настройки серверов.
#
# Логирование ведется в файле master.log.
# Рекомендуется запускать этот скрипт от root (или через sudo).

LOGFILE="$(pwd)/master.log"

# Функция логирования с меткой времени
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

# Проверка запуска от root
if [ "$EUID" -ne 0 ]; then
    log "WARNING: Рекомендуется запускать этот скрипт от root или через sudo."
fi

log "=== Начало развертывания через master.sh ==="

install_packages() {
    if [ -f /etc/debian_version ]; then
        log "Debian/Ubuntu обнаружены. Устанавливаю пакеты..."
        sudo apt update
        sudo apt install -y genisoimage qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils terraform ansible cloud-utils jq git openssh-server
        # Дополнительно: установка необходимых коллекций Ansible
        ansible-galaxy collection install ansible.posix
    elif [ -f /etc/redhat-release ]; then
        log "RHEL/CentOS обнаружены. Устанавливаю пакеты..."
        sudo dnf install -y qemu-kvm libvirt libvirt-client virt-install jq git openssh-server
        if ! rpm -q epel-release &>/dev/null; then
            log "EPEL не найден. Устанавливаю EPEL..."
            sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
        fi
        sudo dnf install -y ansible-core cloud-utils-growpart genisoimage cloud-init
        ansible-galaxy collection install ansible.posix
        if [ ! -f /usr/bin/mkisofs ]; then
            sudo ln -s /usr/bin/genisoimage /usr/bin/mkisofs
        fi
        if ! command -v terraform &>/dev/null; then
            log "Terraform не найден. Скачиваю и устанавливаю Terraform..."
            TERRAFORM_VERSION="1.11.0"  # Укажите нужную версию
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

### 2. (Опционально) Подготовка образа ОС
prepare_os_image() {
    local image_dir="/home/shom/OS_images"
    local image_file="${image_dir}/ubuntu-24.04-server-cloudimg-amd64.img"
    local image_url="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"

    log "Проверяю наличие образа в ${image_file}"
    if [ ! -f "$image_file" ]; then
        log "Образ не найден. Скачиваю ${image_url}..."
        wget -O "$image_file" "$image_url"
        if [ $? -eq 0 ]; then
            log "Образ успешно скачан в ${image_file}"
        else
            log "Ошибка при скачивании образа."
            exit 1
        fi
    else
        log "Образ уже существует: ${image_file}"
    fi
}

### 3. Проверка и создание пользователя "shom" и каталогов
ensure_shom_user_and_dirs() {
    if id "shom" &>/dev/null; then
        log "Пользователь 'shom' уже существует."
    else
        log "Пользователь 'shom' не найден. Создаю пользователя 'shom'..."
        sudo useradd -m -s /bin/bash shom
        if [ $? -ne 0 ]; then
            log "Ошибка при создании пользователя 'shom'."
            exit 1
        fi
    fi

    # Домашний каталог
    if [ ! -d "/home/shom" ]; then
        log "Домашний каталог /home/shom не существует. Создаю его..."
        sudo mkdir -p /home/shom
    fi
    sudo chown shom:shom /home/shom
    sudo chmod 775 /home/shom

    # Каталог для образов
    local image_dir="/home/shom/OS_images"
    if [ ! -d "$image_dir" ]; then
        log "Каталог ${image_dir} не существует. Создаю его..."
        sudo mkdir -p "$image_dir"
    fi
    sudo chown shom:shom "$image_dir"
    sudo chmod 775 "$image_dir"

    # Каталог для пула (создаем подпапку для Gitea)
    local pool_dir="/home/shom/virsh_HDD/gitea_pool"
    if [ ! -d "$pool_dir" ]; then
        log "Каталог ${pool_dir} не существует. Создаю его..."
        sudo mkdir -p "$pool_dir"
    fi
    sudo chown shom:shom "$pool_dir"
    sudo chmod 775 "$pool_dir"

    log "Пользователь 'shom' и каталоги /home/shom, ${image_dir}, ${pool_dir} настроены."
}
ensure_shom_user_and_dirs

# Если хотите автоматически скачивать образ, раскомментируйте следующую строку:
prepare_os_image

### 4. Проверка и создание пула libvirt
create_pool() {
    if ! virsh pool-list --all | grep -q "gitea_pool"; then
        log "Пул 'gitea_pool' не найден. Создаю пул..."
        # Используем новую подпапку /home/shom/virsh_HDD/gitea_pool
        cat <<EOF > gitea_pool.xml
<pool type='dir'>
  <name>gitea_pool</name>
  <target>
    <path>/home/shom/virsh_HDD/gitea_pool</path>
  </target>
</pool>
EOF

        sudo virsh pool-define gitea_pool.xml
        sudo virsh pool-build gitea_pool
        sudo virsh pool-start gitea_pool
        sudo virsh pool-autostart gitea_pool
        rm gitea_pool.xml
        log "Пул 'gitea_pool' успешно создан."
    else
        log "Пул 'gitea_pool' уже существует."
    fi

    # Если SELinux включен, установить нужный контекст для каталога пула
    if command -v getenforce &>/dev/null && [ "$(getenforce)" = "Enforcing" ]; then
        log "SELinux включен. Устанавливаю контекст безопасности для /home/shom/virsh_HDD..."
        sudo chcon -R -t svirt_image_t /home/shom/virsh_HDD
    fi
}
create_pool

### 5. Добавление пользователя "shom" в группу libvirt
#log "Добавляю пользователя shom в группу libvirt..."
#sudo usermod -aG libvirt shom
# Для применения изменений в текущей сессии можно выполнить:
#newgrp libvirt
#КОМАНДА newgrp ВЫЗЫВАЕТ ПЕРЕКЛЮЧЕНИЕ КОНТЕКСТА ОБОЛОЧКИ И ПРЕРВЫАЕТ ИЗ_ЗА ЭТОГО СКРИПТ!!!

### 6. Запуск Terraform для создания виртуальных машин
log "Запуск Terraform..."
cd terraform || { log "Не удалось перейти в каталог terraform"; exit 1; }

log "Инициализация Terraform..."
terraform init | tee -a "$LOGFILE"
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    log "Ошибка: terraform init завершился с ошибкой."
    exit 1
fi

log "Планирование Terraform..."
terraform plan | tee -a "$LOGFILE"
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    log "Ошибка: terraform plan завершился с ошибкой."
    exit 1
fi

log "Применение Terraform..."
terraform apply -auto-approve | tee -a "$LOGFILE"
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    log "Ошибка: terraform apply завершился с ошибкой."
    exit 1
fi
cd .. || exit 1
log "Terraform успешно завершился."


# После Terraform и перед Ansible
echo "Ожидание инициализации SSH..."
sleep 30  # Ожидание 30 секунд

### 7. Обновление known_hosts для созданных серверов
log "Обновление known_hosts..."
for ip in 192.168.122.101 192.168.122.102 192.168.122.103; do
  ssh-keyscan -H "$ip" >> ~/.ssh/known_hosts 2>/dev/null
done

### 8. Запуск Ansible playbook для дальнейшей настройки серверов
log "Запуск Ansible playbook..."
cd ansible || { log "Не удалось перейти в каталог ansible"; exit 1; }
ansible-playbook -i inventory.ini playbook.yml | tee -a "$LOGFILE"
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    log "Ошибка: Ansible playbook завершился с ошибкой."
    exit 1
fi
cd .. || exit 1
log "Ansible playbook успешно выполнен."
log "=== Развертывание завершено успешно ==="

exit 0

