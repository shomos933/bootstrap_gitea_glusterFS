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
  description = "Путь к образу Debian minimal в формате qcow2"
  type        = string
  default     = "/home/shom/OS_images/debian-12-nocloud-amd64-20250316-2053.qcow2"
}

variable "static_ips" {
  description = "Список статических IP для виртуальных машин"
  type        = list(string)
  default     = ["192.168.122.101", "192.168.122.102"]
}

variable "default_user" {
  description = "Имя пользователя для подключения, создаваемого через cloud-init"
  type        = string
  default     = "shom"
}

