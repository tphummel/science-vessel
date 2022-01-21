variable "project_name" {
  default = "cowrie"
}

variable "tenancy_ocid" {}

variable "user_ocid" {}

variable "fingerprint" {}

variable "private_key_path" {}

variable "ssh_public_key_path" {}

variable "region" {
  default = "us-ashburn-1"
}

variable "availability_domain" {}

variable "instance_shape" {
  # free tier eligible
  default = "VM.Standard.E2.1.Micro"
}

variable "image_ocid" {
  # canonical ubuntu 20.04 minimal ashburn
  # default = "ocid1.image.oc1.iad.aaaaaaaawwax2iqkcrg65cxr3w656erbgsb2v7pcjbsm45aocl5qic24h2va"

  # centos 8 ashburn
  default = "ocid1.image.oc1.iad.aaaaaaaagubx53kzend5acdvvayliuna2fs623ytlwalehfte7z2zdq7f6ya"
}

# same cidr used for the vcn and subnet
variable "vcn_subnet_cidr" {
  default = "10.99.0.0/30"
}

terraform {
  required_providers {
    oci = {
      source = "hashicorp/oci"
      version = "4.59.0"
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

resource "oci_core_vcn" "cowrie" {
  cidr_block     = var.vcn_subnet_cidr
  compartment_id = var.tenancy_ocid
  display_name   = var.project_name
  dns_label      = "cowrie"
}

resource "oci_core_internet_gateway" "cowrie" {
  compartment_id = var.tenancy_ocid
  display_name   = var.project_name
  vcn_id = oci_core_vcn.cowrie.id
}

resource "oci_core_route_table" "cowrie" {
  compartment_id = var.tenancy_ocid
  display_name   = var.project_name

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.cowrie.id
  }

  vcn_id = oci_core_vcn.cowrie.id
}

resource "oci_core_security_list" "cowrie" {
  compartment_id = var.tenancy_ocid
  display_name   = var.project_name

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  # https://github.com/trailofbits/cowrie/blob/master/docs/firewalls.md
  ingress_security_rules {
    # Options are supported only for ICMP ("1"), TCP ("6"), UDP ("17"), and ICMPv6 ("58").
    protocol = 6
    source   = "0.0.0.0/0"

    tcp_options {
      max = 22
      min = 22
    }
  }

  # ingress_security_rules {
  #   # Options are supported only for ICMP ("1"), TCP ("6"), UDP ("17"), and ICMPv6 ("58").
  #   protocol = 6
  #   source   = "0.0.0.0/0"
  #
  #   tcp_options {
  #     max = 2222
  #     min = 2222
  #   }
  # }

  vcn_id = oci_core_vcn.cowrie.id
}

resource "oci_core_subnet" "cowrie" {
  cidr_block                 = var.vcn_subnet_cidr
  compartment_id             = var.tenancy_ocid
  display_name               = var.project_name
  dns_label                  = "cowriesub"
  prohibit_public_ip_on_vnic = false
  route_table_id             = oci_core_route_table.cowrie.id
  security_list_ids          = [oci_core_security_list.cowrie.id]
  vcn_id                     = oci_core_vcn.cowrie.id
}

resource "oci_core_instance" "cowrie" {
  availability_domain = var.availability_domain
  compartment_id      = var.tenancy_ocid

  create_vnic_details {
    assign_public_ip = true
    display_name     = var.project_name
    hostname_label   = "cowrie"
    subnet_id        = oci_core_subnet.cowrie.id
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

  source_details {
    boot_volume_size_in_gbs = 50
    source_type             = "image"
    source_id               = var.image_ocid
  }

  timeouts {
    create = "60m"
  }
}
