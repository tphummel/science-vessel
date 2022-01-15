variable "project_name" {
  default = "algo-vpn"
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
  default = "ocid1.image.oc1.iad.aaaaaaaawwax2iqkcrg65cxr3w656erbgsb2v7pcjbsm45aocl5qic24h2va"
}

# same cidr used for the vcn and subnet
variable "vcn_subnet_cidr" {
  default = "10.99.0.0/30"
}

terraform {
  required_providers {
    oci = {
      source = "hashicorp/oci"
      version = "4.13.0"
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

resource "oci_core_vcn" "algo" {
  cidr_block     = var.vcn_subnet_cidr
  compartment_id = var.tenancy_ocid
  display_name   = var.project_name
  dns_label      = "algovpn"
}

resource "oci_core_internet_gateway" "algo" {
  compartment_id = var.tenancy_ocid
  display_name   = var.project_name
  vcn_id = oci_core_vcn.algo.id
}

resource "oci_core_route_table" "algo" {
  compartment_id = var.tenancy_ocid
  display_name   = var.project_name

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.algo.id
  }

  vcn_id = oci_core_vcn.algo.id
}

resource "oci_core_security_list" "algo" {
  compartment_id = var.tenancy_ocid
  display_name   = var.project_name

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  # https://github.com/trailofbits/algo/blob/master/docs/firewalls.md
  ingress_security_rules {
    # allow udp
    protocol = 17
    source   = "0.0.0.0/0"

    udp_options {
      min = 51820
      max = 51820
    }
  }

  vcn_id = oci_core_vcn.algo.id
}

resource "oci_core_subnet" "algo" {
  cidr_block                 = var.vcn_subnet_cidr
  compartment_id             = var.tenancy_ocid
  display_name               = var.project_name
  dns_label                  = "algosub"
  prohibit_public_ip_on_vnic = false
  route_table_id             = oci_core_route_table.algo.id
  security_list_ids          = [oci_core_security_list.algo.id]
  vcn_id                     = oci_core_vcn.algo.id
}

resource "oci_core_instance" "algo" {
  availability_domain = var.availability_domain
  compartment_id      = var.tenancy_ocid

  create_vnic_details {
    assign_public_ip = true
    display_name     = var.project_name
    hostname_label   = "algo"
    subnet_id        = oci_core_subnet.algo.id
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
