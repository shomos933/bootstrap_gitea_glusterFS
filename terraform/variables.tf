// Объявляем переменные для конфигурации виртуальных машин

variable "ssh_public_key" {
  description = "Path to SSH public key"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "vm_count" {
  description = "Количество виртуальных машин для установки Gitea"
  type        = number
  default     = 2
}

variable "vm_memory" {
  description = "Оперативная память для каждой ВМ в МБ"
  type        = number
  default     = 512
}

variable "vm_vcpu" {
  description = "Количество виртуальных CPU для каждой ВМ"
  type        = number
  default     = 1
}

variable "vm_image_path" {
  description = "Путь к образу Ubuntu 24.04 server cloud (qcow2)"
  type        = string
  default     = "/home/shom/OS_images/ubuntu-24.04-server-cloudimg-amd64.img"
}

variable "static_ips" {
  description = "Список статических IP для виртуальных машин"
  type        = list(string)
  default     = ["192.168.124.101", "192.168.124.102"]
}

variable "default_user" {
  description = "Имя пользователя для подключения, создаваемого через cloud-init"
  type        = string
  default     = "ubuntu"
}

// Параметры для NFS-ВМ
variable "nfs_ip" {
  description = "Статический IP для NFS узла"
  type        = string
  default     = "192.168.124.103"
}
variable "nfs_memory" {
  description = "Оперативная память для NFS-ВМ (в МБ)"
  type        = number
  default     = 512
}
variable "nfs_vcpu" {
  description = "Количество виртуальных CPU для NFS-ВМ"
  type        = number
  default     = 1
}
