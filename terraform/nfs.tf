# Создание отдельного пула для NFS (если хотите отделить диски)
resource "libvirt_pool" "nfs_pool" {
  name = "nfs_pool"
  type = "dir"
  target {
    path = "/var/lib/libvirt/nfs_pool" # Замените на желаемый путь
  }
}

# Создание виртуального диска для NFS-ВМ
resource "libvirt_volume" "nfs_vm_disk" {
  name   = "nfs_node_disk.qcow2"
  pool   = libvirt_pool.nfs_pool.name
  source = var.vm_image_path
  format = "qcow2"
}

# Изменение размера диска до 30 ГБ
resource "null_resource" "resize_nfs_volume" {
  provisioner "local-exec" {
    command = "qemu-img resize /var/lib/libvirt/nfs_pool/nfs_node_disk.qcow2 35G"
  }
  depends_on = [libvirt_volume.nfs_vm_disk]
}

# Генерация cloud-init ISO для NFS-ВМ
resource "libvirt_cloudinit_disk" "nfs_cloudinit" {
  name      = "nfs_cloudinit.iso"
  pool      = libvirt_pool.nfs_pool.name
  user_data = templatefile("${path.module}/cloud-init.cfg", {
    hostname     = "nfs-node"
    default_user = var.default_user  # Если для NFS используется ubuntu, то оставить "ubuntu"
    static_ip    = var.nfs_ip
    ssh_key      = file(pathexpand(var.ssh_public_key))
  })
}

# Создание виртуальной машины NFS-узла
resource "libvirt_domain" "nfs_node" {
  name   = "nfs-node"
  memory = var.nfs_memory
  vcpu   = var.nfs_vcpu

# ДОБАВЛЕНО: Указываем, что домен зависит от завершения ресайза диска
  depends_on = [
    null_resource.resize_nfs_volume,
    libvirt_cloudinit_disk.nfs_cloudinit # Можно оставить и зависимость от cloudinit на всякий случай
  ]

  disk {
    volume_id = libvirt_volume.nfs_vm_disk.id
  }

  cloudinit = libvirt_cloudinit_disk.nfs_cloudinit.id

  network_interface {
    network_name = libvirt_network.gitea_net.name
    addresses    = [ var.nfs_ip ]
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

