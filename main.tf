variable "project_name" {
  default = "science-vessel-2024"
}

variable "tenancy_ocid" {}

variable "object_storage_namespace" {}

variable "user_ocid" {}

variable "fingerprint" {}

variable "private_key_path" {}

variable "ssh_public_key_path" {}

variable "ssh_port" {}

locals {
  ssh_private_key_path = replace(var.ssh_public_key_path, ".pub", "")
}

variable "region" {
  default = "us-ashburn-1"
}

variable "availability_domain" {}

variable "instance_shape" {
  # free tier eligible
  default = "VM.Standard.A1.Flex"
}

variable "image_ocid" {
  # canonical ubuntu 20.04 minimal ashburn
  # default = "ocid1.image.oc1.iad.aaaaaaaawwax2iqkcrg65cxr3w656erbgsb2v7pcjbsm45aocl5qic24h2va"

  # centos 8 ashburn
  # default = "ocid1.image.oc1.iad.aaaaaaaagubx53kzend5acdvvayliuna2fs623ytlwalehfte7z2zdq7f6ya"

  # canonical ubunutu 22.04 aarch64 ashburn
  default = "ocid1.image.oc1.iad.aaaaaaaa2el7vv6ym4snc2gm5seaikafu3c4uwh2kuhhlsv2wpkdonjdom5a"
}

# same cidr used for the vcn and subnet
variable "vcn_subnet_cidr" {
  default = "10.99.0.0/30"
}

terraform {
  required_providers {
    oci = {
      source = "hashicorp/oci"
      version = "6.8.0"
    }
  }
}

provider "oci" {
  tenancy_ocid = var.tenancy_ocid
  user_ocid = var.user_ocid
  fingerprint = var.fingerprint
  private_key_path = var.private_key_path
  region = var.region
  disable_auto_retries = true
}

data "oci_identity_availability_domains" "all" {
  compartment_id = var.tenancy_ocid
}

data "oci_identity_tenancy" "tenancy" {
  tenancy_id = var.tenancy_ocid
}

# get the tenancy's home region
data "oci_identity_regions" "home_region" {
  filter {
    name   = "key"
    values = [data.oci_identity_tenancy.tenancy.home_region_key]
  }
}

resource "oci_core_vcn" "science_vessel" {
  cidr_block     = var.vcn_subnet_cidr
  compartment_id = var.tenancy_ocid
  display_name   = var.project_name
  dns_label      = "scives"
}

resource "oci_core_internet_gateway" "science_vessel" {
  compartment_id = var.tenancy_ocid
  display_name   = var.project_name
  vcn_id = oci_core_vcn.science_vessel.id
}

resource "oci_core_route_table" "science_vessel" {
  compartment_id = var.tenancy_ocid
  display_name   = var.project_name

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.science_vessel.id
  }

  vcn_id = oci_core_vcn.science_vessel.id
}

resource "oci_core_security_list" "science_vessel" {
  compartment_id = var.tenancy_ocid
  display_name   = var.project_name

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  # https://github.com/trailofbits/science_vessel/blob/master/docs/firewalls.md
  ingress_security_rules {
    # Options are supported only for ICMP ("1"), TCP ("6"), UDP ("17"), and ICMPv6 ("58").
    protocol = 6
    source   = "0.0.0.0/0"

    tcp_options {
      max = 22
      min = 22
    }
  }

  ingress_security_rules {
    # Options are supported only for ICMP ("1"), TCP ("6"), UDP ("17"), and ICMPv6 ("58").
    protocol = 6
    source   = "0.0.0.0/0"
  
    tcp_options {
      max = var.ssh_port
      min = var.ssh_port
    }
  }

  vcn_id = oci_core_vcn.science_vessel.id
}

resource "oci_core_subnet" "science_vessel" {
  cidr_block                 = var.vcn_subnet_cidr
  compartment_id             = var.tenancy_ocid
  display_name               = var.project_name
  dns_label                  = "scivessub"
  prohibit_public_ip_on_vnic = false
  route_table_id             = oci_core_route_table.science_vessel.id
  security_list_ids          = [oci_core_security_list.science_vessel.id]
  vcn_id                     = oci_core_vcn.science_vessel.id
}

resource "oci_core_instance" "science_vessel" {
  availability_domain = var.availability_domain
  compartment_id      = var.tenancy_ocid

  create_vnic_details {
    assign_public_ip = true
    display_name     = var.project_name
    hostname_label   = "sciencevessel"
    subnet_id        = oci_core_subnet.science_vessel.id
  }

  display_name = var.project_name

  launch_options {
    boot_volume_type = "PARAVIRTUALIZED"
    network_type     = "PARAVIRTUALIZED"
  }

  # prevent the instance from destroying and recreating itself if the image ocid changes
  lifecycle {
    ignore_changes = [source_details[0].source_id]
  }

  metadata = {
    ssh_authorized_keys = file(var.ssh_public_key_path)
  }

  shape = var.instance_shape
  shape_config {
    ocpus = 2
    memory_in_gbs = 12
  }

  source_details {
    boot_volume_size_in_gbs = 50
    source_type             = "image"
    source_id               = var.image_ocid
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update -y",
      "sudo systemctl stop iptables",
      "sudo systemctl disable iptables",
      "sudo apt remove iptables-persistent -y",
      "sudo iptables -F",
      "sudo iptables -X",
      "sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak",
      "sudo sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config",
      "sudo sed -i 's/X11Forwarding yes/X11Forwarding no/' /etc/ssh/sshd_config",
      "sudo sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config",
      "sudo sed -i 's/#Port 22/Port ${var.ssh_port}/' /etc/ssh/sshd_config",
      "sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config",      
      "sudo bash -c 'echo \"Protocol 2\" >> /etc/ssh/sshd_config'",
      "sudo bash -c 'echo \"MaxAuthTries 3\" >> /etc/ssh/sshd_config'",
      "sudo bash -c 'echo \"AllowTcpForwarding yes\" >> /etc/ssh/sshd_config'",
      "sudo bash -c 'echo \"ClientAliveInterval 300\" >> /etc/ssh/sshd_config'",
      "sudo bash -c 'echo \"ClientAliveCountMax 2\" >> /etc/ssh/sshd_config'",
      "sudo systemctl restart ssh"
    ]
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(local.ssh_private_key_path)
    host        = self.public_ip
  }


  timeouts {
    create = "60m"
  }
}

resource "oci_objectstorage_bucket" "science_vessel" {
  #Required
  compartment_id = var.tenancy_ocid
  name = var.project_name
  namespace = var.object_storage_namespace

  #Optional
  access_type = "NoPublicAccess"
  object_events_enabled = false
  storage_tier = "Standard"
  versioning = "Disabled"
}

resource "oci_identity_dynamic_group" "science_vessel" {
  compartment_id = var.tenancy_ocid
  description = "all compute instances in tenancy"
  matching_rule = "instance.compartment.id = '${var.tenancy_ocid}'"
  name = var.project_name
}

# policy allow dg to write objects to bucket
resource "oci_identity_policy" "science_vessel" {
  #Required
  compartment_id = var.tenancy_ocid
  description = var.project_name
  name = var.project_name
  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.science_vessel.name} to read buckets in tenancy",
    "Allow dynamic-group ${oci_identity_dynamic_group.science_vessel.name} to manage objects in tenancy where any {request.permission='OBJECT_CREATE', request.permission='OBJECT_INSPECT'}"
  ]
}

output "science_vessel_public_ip" {
  value = oci_core_instance.science_vessel.public_ip
}

output "science_vessel_ssh_port" {
  value = var.ssh_port
}