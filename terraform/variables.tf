// Объявляем переменные для конфигурации виртуальных машин

variable "ssh_public_key" {
  description = "Path to SSH public key"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

// Количество создаваемых виртуальных машин
variable "vm_count" {
  description = "Количество виртуальных машин для установки Gitea"
  type        = number
  default     = 2
}

// Объём оперативной памяти (в МБ) для каждой ВМ
variable "vm_memory" {
  description = "Оперативная память для каждой ВМ в МБ"
  type        = number
  default     = 512
}

// Количество vCPU для каждой ВМ
variable "vm_vcpu" {
  description = "Количество виртуальных CPU для каждой ВМ"
  type        = number
  default     = 1
}

// Путь к базовому образу Debian minimal (скачайте его с официального сайта Debian Cloud Images)
variable "vm_image_path" {
  description = "Путь к образу Debian minimal в формате qcow2"
  type        = string
  default     = "/home/shom/OS_images/debian-12-nocloud-amd64-20250316-2053.qcow2"
}

// Статические IP-адреса для ВМ
variable "static_ips" {
  description = "Список статических IP для виртуальных машин"
  type        = list(string)
  default     = ["192.168.122.101", "192.168.122.102"]
}

// Имя пользователя, который будет создан через cloud-init (в нашем случае \"shom\")
variable "default_user" {
  description = "Имя пользователя для подключения, создаваемого через cloud-init"
  type        = string
  default     = "shom"
}

