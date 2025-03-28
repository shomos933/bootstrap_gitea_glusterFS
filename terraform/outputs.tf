output "vm_names" {
  value = [for domain in libvirt_domain.gitea_nodes : domain.name]
}

