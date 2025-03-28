# Terraform и провайдер
terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.7.0"
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
  pool   = "default"
  source = var.vm_image_path
  format = "qcow2"
}
resource "null_resource" "resize_volume" {
  count = var.vm_count

  provisioner "local-exec" {
    command = "qemu-img resize /home/virsh/HDD_virt/gitea_node_disk_${count.index + 1}.qcow2 7G"
  }

  depends_on = [libvirt_volume.vm_volume]
}

# Генерация cloud-init ISO для каждой ВМ с использованием шаблона cloud-init.cfg
resource "libvirt_cloudinit_disk" "commoninit" {
  count     = var.vm_count
  name      = "cloudinit-${count.index + 1}.iso"
  pool      = "default"  # Add this line to specify the storage pool
  user_data = templatefile("${path.module}/cloud-init.cfg", {
    hostname     = "gitea-node-${count.index + 1}"
    default_user = var.default_user
    static_ip    = var.static_ips[count.index]
    ssh_key      = file(pathexpand(var.ssh_public_key))
  })
}
# Создание виртуальных машин
resource "libvirt_domain" "gitea_nodes" {
  count  = var.vm_count
  name   = "gitea-node-${count.index + 1}"
  memory = var.vm_memory
  vcpu   = var.vm_vcpu

  # Основной диск
  # Диск с cloud-init для первичной настройки
  disk {
    volume_id = libvirt_volume.vm_volume[count.index].id
  }
  
  # Use this instead of the disk block for cloud-init
  cloudinit = libvirt_cloudinit_disk.commoninit[count.index].id

  # Сетевой интерфейс с назначением статического IP
  network_interface {
    network_name = "default"
    addresses    = [ var.static_ips[count.index] ]
  }

  console {
    type        = "pty"
    target_port = "0"  # Добавлен target_port
  }
  graphics {
    type        = "vnc"
    listen_type = "address"
    listen_address = "0.0.0.0" # Listen on all interfaces (change if needed)
  }
}
