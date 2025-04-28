output "vm_names" {
  value = concat(
    [for domain in libvirt_domain.gitea_nodes : domain.name],
    [libvirt_domain.nfs_node.name]       
  )
}

