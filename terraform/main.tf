terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.8.3"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9.1"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

# Создание виртуальных дисков на основе базового образа
resource "libvirt_volume" "vm_volume" {
  count  = var.vm_count
  name   = "gitea_node_disk_${count.index + 1}.qcow2"
  pool   = "gitea_pool"
  source = var.vm_image_path
  format = "qcow2"
}

# Изменение размера диска до 7G
resource "null_resource" "resize_volume" {
  count = var.vm_count

  provisioner "local-exec" {
    command = "qemu-img resize /home/shom/virsh_HDD/gitea_pool/gitea_node_disk_${count.index + 1}.qcow2 7G"
  }

  depends_on = [libvirt_volume.vm_volume]
}

# Добавляем задержку, чтобы убедиться, что resize завершился и блокировка снята
resource "time_sleep" "wait_after_resize" {
  create_duration = "10s"
  depends_on = [null_resource.resize_volume]
}

# (Опционально) Фикс прав доступа, если потребуется (можно оставить, если не вызывает проблем)
# resource "null_resource" "fix_permissions" {
#   count = var.vm_count
#
#   provisioner "local-exec" {
#     command = "sudo chown qemu:qemu /home/shom/virsh_HDD/gitea_pool/gitea_node_disk_${count.index + 1}.qcow2 && sudo chmod 660 /home/shom/virsh_HDD/gitea_pool/gitea_node_disk_${count.index + 1}.qcow2"
#   }
#
#   depends_on = [time_sleep.wait_after_resize]
# }

# Генерация cloud-init ISO для каждой ВМ с использованием шаблона cloud-init.cfg
resource "libvirt_cloudinit_disk" "commoninit" {
  count     = var.vm_count
  name      = "cloudinit-${count.index + 1}.iso"
  pool      = "gitea_pool"
  user_data = templatefile("${path.module}/cloud-init.cfg", {
    hostname     = "gitea-node-${count.index + 1}"
    default_user = var.default_user
    static_ip    = var.static_ips[count.index]
    ssh_key      = file(pathexpand(var.ssh_public_key))
  })
  depends_on = [time_sleep.wait_after_resize]
}

# Создание виртуальных машин
resource "libvirt_domain" "gitea_nodes" {
  count  = var.vm_count
  name   = "gitea-node-${count.index + 1}"
  memory = var.vm_memory
  vcpu   = var.vm_vcpu

  # Основной диск
  disk {
    volume_id = libvirt_volume.vm_volume[count.index].id
  }
  
  # Использование cloud-init (без отдельного диска)
  cloudinit = libvirt_cloudinit_disk.commoninit[count.index].id

  # Сетевой интерфейс с назначением статического IP
  network_interface {
    network_name = "default"
    addresses    = [ var.static_ips[count.index] ]
  }

  console {
    type        = "pty"
    target_port = "0"
  }
  graphics {
    type           = "vnc"
    listen_type    = "address"
    listen_address = "0.0.0.0"
  }
}

