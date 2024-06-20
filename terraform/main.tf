resource "yandex_vpc_network" "network-tf" {
  name = "network-tf"
}

resource "yandex_vpc_subnet" "subnet-tf" {
  name           = "subnet-tf"
  zone           = var.zone
  network_id     = yandex_vpc_network.network-tf.id
  v4_cidr_blocks = ["192.168.10.0/24"]
  depends_on     = [yandex_vpc_network.network-tf]
}

resource "yandex_compute_disk" "boot-disk" {
  count    = 2
  name     = "boot-disk-${count.index + 1}"
  type     = "network-hdd"
  zone     = var.zone
  size     = "20"
  image_id = "fd89jk9j9vifp28uprop"
}

resource "yandex_compute_instance" "vm" {
  count = 2
  name  = "terraform${count.index + 1}"
  resources {
    cores  = 2
    memory = 2
  }
  boot_disk {
    disk_id = yandex_compute_disk.boot-disk[count.index].id
  }
  network_interface {
    subnet_id          = yandex_vpc_subnet.subnet-tf.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.sg-vms.id]
  }
  metadata = {
    user-data = "${file("meta.txt")}"
  }
  depends_on = [yandex_vpc_subnet.subnet-tf, yandex_vpc_security_group.sg-vms]
}

resource "yandex_vpc_security_group" "sg-balancer" {
  name       = "sg-balancer"
  network_id = yandex_vpc_network.network-tf.id
  egress {
    protocol       = "ANY"
    description    = "any"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
  ingress {
    protocol       = "TCP"
    description    = "ext-http"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }
  ingress {
    protocol       = "TCP"
    description    = "ext-https"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }
  ingress {
    protocol          = "TCP"
    description       = "healthchecks"
    predefined_target = "loadbalancer_healthchecks"
    port              = 30080
  }
}

resource "yandex_vpc_security_group" "sg-vms" {
  name       = "sg-vms"
  network_id = yandex_vpc_network.network-tf.id
  ingress {
    protocol       = "TCP"
    description    = "balancer1"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    protocol       = "TCP"
    description    = "ssh"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }
  ingress {
    protocol       = "TCP"
    description    = "balancer2"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 3000
  }
  egress {
    protocol       = "ANY"
    description    = "any"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

resource "yandex_vpc_address" "stat_address" {
  name = "alb-static-address"
  external_ipv4_address {
    zone_id = var.zone
  }
}

resource "yandex_alb_target_group" "target-group" {
  name = "target-group"
  target {
    subnet_id  = yandex_vpc_subnet.subnet-tf.id
    ip_address = yandex_compute_instance.vm[0].network_interface[0].ip_address
  }
  target {
    subnet_id  = yandex_vpc_subnet.subnet-tf.id
    ip_address = yandex_compute_instance.vm[1].network_interface[0].ip_address
  }
  depends_on = [yandex_compute_instance.vm[0], yandex_compute_instance.vm[1]]
}

resource "yandex_alb_backend_group" "backend-group" {
  name = "backend-group"
  session_affinity {
    connection {
      source_ip = true
    }
  }
  http_backend {
    name             = "backend"
    weight           = 1
    port             = 3000
    target_group_ids = [yandex_alb_target_group.target-group.id]
    load_balancing_config {
      panic_threshold = 90
      mode            = "MAGLEV_HASH"
    }
    healthcheck {
      timeout             = "10s"
      interval            = "2s"
      healthy_threshold   = 10
      unhealthy_threshold = 15
      http_healthcheck {
        path = "/"
      }
    }
  }
  depends_on = [yandex_alb_target_group.target-group]
}

resource "yandex_alb_http_router" "router" {
  name = "router"
  labels = {
    tf-label    = "tf-label"
    empty-label = ""
  }
}

resource "yandex_alb_virtual_host" "virtual-host" {
  name           = "virtual-host"
  http_router_id = yandex_alb_http_router.router.id
  route {
    name = "route"
    http_route {
      http_route_action {
        backend_group_id = yandex_alb_backend_group.backend-group.id
        timeout          = "60s"
      }
    }
  }
  depends_on = [yandex_alb_backend_group.backend-group, yandex_alb_http_router.router]
}

data "ansiblevault_path" "certificate" {
  path = var.ansible_vault_path
  key  = "certificate"
}

data "ansiblevault_path" "private_key" {
  path = var.ansible_vault_path
  key  = "private_key"
}


resource "yandex_cm_certificate" "imported-cert" {
  name = "imported-cert"
  self_managed {
    certificate = data.ansiblevault_path.certificate.value
    private_key = data.ansiblevault_path.private_key.value
  }
}

resource "yandex_alb_load_balancer" "l7-balancer" {
  name       = "l7-balancer"
  network_id = yandex_vpc_network.network-tf.id
  allocation_policy {
    location {
      zone_id   = var.zone
      subnet_id = yandex_vpc_subnet.subnet-tf.id
    }
  }
  listener {
    name = "listener-443"
    endpoint {
      address {
        external_ipv4_address {
          address = yandex_vpc_address.stat_address.external_ipv4_address[0].address
        }
      }
      ports = [443]
    }
    tls {
      default_handler {
        certificate_ids = [yandex_cm_certificate.imported-cert.id]
        http_handler {
          http_router_id = yandex_alb_http_router.router.id
        }
      }
    }
  }
  listener {
    name = "listener-80"
    endpoint {
      address {
        external_ipv4_address {
          address = yandex_vpc_address.stat_address.external_ipv4_address[0].address
        }
      }
      ports = [80]
    }
    http {
      redirects {
        http_to_https = true
      }
    }
  }
  log_options {
    discard_rule {
      http_code_intervals = ["HTTP_2XX", "HTTP_5XX"]
      discard_percent     = 75
    }
  }
  depends_on = [
    yandex_vpc_network.network-tf,
    yandex_vpc_subnet.subnet-tf,
    yandex_alb_http_router.router,
    yandex_cm_certificate.imported-cert
  ]
}

resource "yandex_dns_zone" "mokretsov_ru_zone" {
  name        = "mokretsov-ru-zone"
  description = "DNS zone for mokretsov.ru"
  zone        = "mokretsov.ru."
  public      = true
}

resource "yandex_dns_recordset" "mokretsov_ru_a_record" {
  zone_id    = yandex_dns_zone.mokretsov_ru_zone.id
  name       = "@"
  type       = "A"
  ttl        = 60
  data       = [yandex_vpc_address.stat_address.external_ipv4_address[0].address]
  depends_on = [yandex_dns_zone.mokretsov_ru_zone, yandex_alb_load_balancer.l7-balancer]
}

resource "yandex_dns_recordset" "mokretsov_ru_www_a_record" {
  zone_id    = yandex_dns_zone.mokretsov_ru_zone.id
  name       = "www"
  type       = "A"
  ttl        = 60
  data       = [yandex_vpc_address.stat_address.external_ipv4_address[0].address]
  depends_on = [yandex_dns_zone.mokretsov_ru_zone, yandex_alb_load_balancer.l7-balancer]
}

data "ansiblevault_path" "db_user" {
  path = var.ansible_vault_path
  key  = "db_user"
}

data "ansiblevault_path" "db_password" {
  path = var.ansible_vault_path
  key  = "db_password"
}

data "ansiblevault_path" "db_name" {
  path = var.ansible_vault_path
  key  = "db_name"
}

resource "yandex_mdb_postgresql_cluster" "dbcluster" {
  name        = "tfhexlet"
  environment = "PRESTABLE"
  network_id  = yandex_vpc_network.network-tf.id
  config {
    version = "14"
    resources {
      resource_preset_id = "s2.micro"
      disk_type_id       = "network-ssd"
      disk_size          = 15
    }
    postgresql_config = {
      max_connections = 100
    }
  }
  maintenance_window {
    type = "WEEKLY"
    day  = "SAT"
    hour = 12
  }
  host {
    zone      = var.zone
    subnet_id = yandex_vpc_subnet.subnet-tf.id
  }
}

resource "yandex_mdb_postgresql_user" "dbuser" {
  cluster_id = yandex_mdb_postgresql_cluster.dbcluster.id
  name       = data.ansiblevault_path.db_user.value
  password   = data.ansiblevault_path.db_password.value
  depends_on = [yandex_mdb_postgresql_cluster.dbcluster]
}

resource "yandex_mdb_postgresql_database" "db" {
  cluster_id = yandex_mdb_postgresql_cluster.dbcluster.id
  name       = data.ansiblevault_path.db_name.value
  owner      = yandex_mdb_postgresql_user.dbuser.name
  lc_collate = "en_US.UTF-8"
  lc_type    = "en_US.UTF-8"
  depends_on = [yandex_mdb_postgresql_cluster.dbcluster]
}

output "db_host" {
  value = yandex_mdb_postgresql_cluster.dbcluster.host[0].fqdn
}

resource "local_file" "ansible_vars" {
  content = templatefile("templates/terraform-outputs.tftpl",
    {
      db_host = yandex_mdb_postgresql_cluster.dbcluster.host[0].fqdn
  })
  filename   = "../ansible/group_vars/all/terraform-outputs.yml"
  depends_on = [yandex_mdb_postgresql_cluster.dbcluster]
}

resource "local_file" "ansible_inventory" {
  content = templatefile("templates/inventory.tftpl",
    {
      vm1_ip = yandex_compute_instance.vm[0].network_interface[0].nat_ip_address,
      vm2_ip = yandex_compute_instance.vm[1].network_interface[0].nat_ip_address
  })
  filename = "../ansible/inventory.yml"
  depends_on = [
    yandex_compute_instance.vm[0],
    yandex_compute_instance.vm[1]
  ]
}