resource "libvirt_network" "gitea_net" {
  name       = "gitea-net"
  autostart  = true
  mode       = "nat"
  addresses  = ["192.168.124.0/24"]

}

