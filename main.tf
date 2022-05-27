terraform {
    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = "~> 3.27"
        }
    }
}

provider "aws" {
    alias   = "docdb"
    region  = var.region_docdb
}

provider "aws" {
    alias   = "peer"
    region  = var.region_docdb_peer
}

resource "aws_vpc" "docdb" {
    provider = aws.docdb
    cidr_block = var.vpc_cidr_docdb
}

# Create 1 public subnets for each AZ within the regional VPC
resource "aws_subnet" "public" {
    provider = aws.docdb
    for_each = var.public_subnet_numbers
    vpc_id            = aws_vpc.docdb.id
    availability_zone = each.key
    # 2,048 IP addresses each
    cidr_block = cidrsubnet(aws_vpc.docdb.cidr_block, 4, each.value)
}
 
# Create 1 private subnets for each AZ within the regional VPC
resource "aws_subnet" "private" {
    provider = aws.docdb
    for_each = var.private_subnet_numbers
    vpc_id            = aws_vpc.docdb.id
    availability_zone = each.key
    # 2,048 IP addresses each
    cidr_block = cidrsubnet(aws_vpc.docdb.cidr_block, 4, each.value)
}

resource "aws_security_group" "docdb" {
    provider = aws.docdb
    vpc_id       = aws_vpc.docdb.id
    name         = "vpc-connect"
    description  = "VPC Connect"

    ingress {
        protocol    = -1
        from_port   = 0
        to_port     = 0
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_docdb_cluster_instance" "cluster_instances" {
    provider            = aws.docdb
    count               = 3
    identifier          = format("%s-%d", var.docdb_cluster_id, "${count.index}")
    cluster_identifier  = aws_docdb_cluster.default.id
    instance_class      = var.instance_class_name
}

resource "aws_docdb_subnet_group" "items" {
    provider            = aws.docdb
    name                = "subnet_docdb"
#    for_each            = concat(aws_subnet.public, aws_subnet.private)
#    subnet_ids          = [aws_subnet.public[*].id, aws_subnet.private[*].id]
    subnet_ids          = concat([for subnet in aws_subnet.public : subnet.id], [for subnet in aws_subnet.private : subnet.id])
#    subnet_ids          = data.aws_subnets.vpc.ids
}

resource "aws_docdb_cluster" "default" {
    provider                = aws.docdb
    cluster_identifier      = var.docdb_cluster_id
    availability_zones      = var.availability_zone_names
    master_username         = var.docdb_cluster_username
    master_password         = var.docdb_cluster_password
    skip_final_snapshot     = true
    deletion_protection     = false
    db_subnet_group_name    = aws_docdb_subnet_group.items.id
    vpc_security_group_ids  = [aws_security_group.docdb.id]
}

data "aws_ami" "amazon_2" {
    provider = aws.peer
    most_recent = true

    filter { 
        name = "name"
        values = ["amzn2-ami-kernel-*-hvm-*-x86_64-gp2"]
    } 
    owners = ["amazon"]
}

data "http" "myip" {
    url = "http://ipv4.icanhazip.com"
}

resource "aws_vpc" "docdb_peer" {
    provider                = aws.peer
    cidr_block              = var.vpc_cidr_docdb_peer
    enable_dns_support      = true
    enable_dns_hostnames    = true
}

resource "aws_internet_gateway" "ig_tunnel" {
    provider                = aws.peer
    vpc_id = "${aws_vpc.docdb_peer.id}"
}

resource "aws_security_group" "tunnel" {
    provider = aws.peer
    vpc_id       = aws_vpc.docdb_peer.id
    name         = "vpc-connect"
    description  = "VPC Connect"
  
    ingress {
        cidr_blocks = ["${chomp(data.http.myip.body)}/32"]
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
    } 

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_subnet" "docdb_peer" {
    provider = aws.peer
    vpc_id                    = aws_vpc.docdb_peer.id
    availability_zone         = "eu-west-1a"
    cidr_block                = var.subnet_cidr_docdb_peer
    map_public_ip_on_launch   = true
}

data "aws_key_pair" "ireland_ofc_new" {
    provider = aws.peer
    key_name   = var.key_name
}

resource "aws_instance" "tunnel-ec2" { 
    provider = aws.peer
    vpc_security_group_ids = ["${aws_security_group.tunnel.id}"]
    subnet_id     = aws_subnet.docdb_peer.id
    ami           = data.aws_ami.amazon_2.id
    instance_type = var.ec2_instance_type_name
    key_name      = var.key_name
    connection {
        type        = "ssh"
        user        = "ec2-user"
        host        = "${aws_instance.tunnel-ec2.public_ip}"
        private_key = file("/home/vizeet/workspace/docdb/terraform/ireland_ofc_new.pem")
        timeout     = "1m"
    }
    provisioner "remote-exec" {
        inline = [
            "sudo yum -y update",
            "echo -e \"[mongodb-org-4.0] \nname=MongoDB Repository\nbaseurl=https://repo.mongodb.org/yum/amazon/2013.03/mongodb-org/4.0/x86_64/\ngpgcheck=1 \nenabled=1 \ngpgkey=https://www.mongodb.org/static/pgp/server-4.0.asc\" | sudo tee /etc/yum.repos.d/mongodb-org-4.0.repo",
            "sudo yum install -y mongodb-org",
            "wget https://s3.amazonaws.com/rds-downloads/rds-combined-ca-bundle.pem"
        ]
    }
}

data "aws_caller_identity" "current" {}

resource "aws_vpc_peering_connection" "peer" {
  provider      = aws.peer
  vpc_id        = aws_vpc.docdb_peer.id
  peer_vpc_id   = aws_vpc.docdb.id
  peer_owner_id = "${data.aws_caller_identity.current.account_id}"
  peer_region   = var.region_docdb
  auto_accept   = false

  tags = {
    Side = "Requester"
  }
}

# Accepter's side of the connection.
resource "aws_vpc_peering_connection_accepter" "peer" {
  provider                  = aws.docdb
  vpc_peering_connection_id = "${aws_vpc_peering_connection.peer.id}"
  auto_accept               = true

  tags = {
    Side = "Accepter"
  }
} 

resource "aws_internet_gateway" "ig_docdb" {
    provider    = aws.docdb
    vpc_id      = "${aws_vpc.docdb.id}"
}

resource "aws_default_route_table" "docdb_peer" {
    provider    = aws.peer
    default_route_table_id = aws_vpc.docdb_peer.default_route_table_id
#    vpc_id      = aws_vpc.docdb_peer.id
    route       = concat([for subnet in aws_subnet.public : {"cidr_block" = subnet.cidr_block, "vpc_peering_connection_id" = aws_vpc_peering_connection.peer.id, "gateway_id" = "", "carrier_gateway_id": "", "destination_prefix_list_id": "", "egress_only_gateway_id": "", "instance_id": "", "ipv6_cidr_block": "", "local_gateway_id": "", "nat_gateway_id": "", "network_interface_id": "", "transit_gateway_id": "", "vpc_endpoint_id": ""}], [for subnet in aws_subnet.private : {"cidr_block" = subnet.cidr_block, "vpc_peering_connection_id" = aws_vpc_peering_connection.peer.id, "gateway_id" = "", "carrier_gateway_id": "", "destination_prefix_list_id": "", "egress_only_gateway_id": "", "instance_id": "", "ipv6_cidr_block": "", "local_gateway_id": "", "nat_gateway_id": "", "network_interface_id": "", "transit_gateway_id": "", "vpc_endpoint_id": ""}])
}

resource "aws_default_route_table" "docdb" {
    provider    = aws.docdb
    default_route_table_id = aws_vpc.docdb.default_route_table_id
#    vpc_id      = aws_vpc.docdb.id
    route       = [{"cidr_block" = aws_subnet.docdb_peer.cidr_block, "vpc_peering_connection_id" = aws_vpc_peering_connection_accepter.peer.id, "gateway_id" = "", "carrier_gateway_id": "", "destination_prefix_list_id": "", "egress_only_gateway_id": "", "instance_id": "", "ipv6_cidr_block": "", "local_gateway_id": "", "nat_gateway_id": "", "network_interface_id": "", "transit_gateway_id": "", "vpc_endpoint_id": ""}]
}

resource "aws_route" "update_tunnel" {
    provider               = aws.peer
    route_table_id         = "${aws_default_route_table.docdb_peer.id}"
    destination_cidr_block = "0.0.0.0/0"
    gateway_id             = "${aws_internet_gateway.ig_tunnel.id}"
}

resource "aws_route" "update_docdb" {
    provider               = aws.docdb
    route_table_id         = "${aws_default_route_table.docdb.id}"
    destination_cidr_block = "0.0.0.0/0"
    gateway_id             = "${aws_internet_gateway.ig_docdb.id}"
}

