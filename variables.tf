variable "ec2_instance_type_name" {
    type    = string
    default = "t2.nano"
}

variable "availability_zone_names" {
    type    = list(string)
    default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "region_docdb" {
    type    = string
    default = "us-east-1"
}

variable "region_docdb_peer" {
    type    = string
    default = "eu-west-1"
}

variable "instance_class_name" {
    type    = string
    default = "db.t3.medium"
}

variable "docdb_cluster_username" {
    type    = string
}

variable "docdb_cluster_password" {
    type    = string
}

variable "key_name" {
    type    = string
    default = "ireland_ofc_new"
}

variable "docdb_cluster_id" {
    type    = string
    default = "docdb-cluster-demo"
}

variable "vpc_cidr_docdb" {
  type        = string
  description = "The IP range to use for the VPC"
  default     = "172.34.0.0/16"
}

variable "vpc_cidr_docdb_peer" {
  type        = string
  description = "The IP range to use for the VPC"
  default     = "172.32.0.0/16"
}

variable "subnet_cidr_docdb_peer" {
  type        = string
  description = "The IP range to use for the VPC"
  default     = "172.32.0.0/20"
}

variable "public_subnet_numbers" {
  type = map(number)
 
  description = "Map of AZ to a number that should be used for public subnets"
 
  default = {
    "us-east-1a" = 1
    "us-east-1b" = 2
    "us-east-1c" = 3
  }
}

variable "private_subnet_numbers" {
  type = map(number)
 
  description = "Map of AZ to a number that should be used for private subnets"
 
  default = {
    "us-east-1a" = 4
    "us-east-1b" = 5
    "us-east-1c" = 6
  }
}
