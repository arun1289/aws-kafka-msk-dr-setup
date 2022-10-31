terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}


provider "aws" {
    region = "us-west-2"
}

provider "aws" {
alias = "ireland"
 region = "eu-west-1"

}

data "aws_vpc" "secondaryvpc" {
  cidr_block = "10.0.0.0/16"
  }

data "aws_vpc" "primaryvpc" {
  provider = aws.ireland
cidr_block = "192.168.0.0/22"
}

data "aws_availability_zones" "azs" {
  state = "available"
}

resource "aws_vpc_peering_connection" "vpcconnection" {
  peer_owner_id = "100828196990"
  peer_vpc_id   = data.aws_vpc.primaryvpc.id
  vpc_id        = data.aws_vpc.secondaryvpc.id
  peer_region   = "eu-west-1"
  auto_accept   = false
    tags = {
    Side = "Requester"
  }
}

resource "aws_vpc_peering_connection_accepter" "peer" {
  provider = aws.ireland
  vpc_peering_connection_id = "${aws_vpc_peering_connection.vpcconnection.id}"
  auto_accept               = true
    tags = {
    Side = "Accepter"
  }
  depends_on = [
    aws_vpc_peering_connection.vpcconnection
  ]
}  

# Create a route table
data "aws_route_table" "rt_primary" {
  provider = aws.ireland
  vpc_id = data.aws_vpc.primaryvpc.id
  depends_on = [
    aws_vpc_peering_connection_accepter.peer
  ]
}

# Create a route
resource "aws_route" "r_primary" {
  provider = aws.ireland
  route_table_id            = data.aws_route_table.rt_primary.id
  destination_cidr_block    = "10.0.0.0/22"
  vpc_peering_connection_id = aws_vpc_peering_connection.vpcconnection.id
  depends_on = [
    data.aws_route_table.rt_primary
  ]
  }

# Create a route table
data "aws_route_table" "rt_secondary" {
  vpc_id = data.aws_vpc.secondaryvpc.id
  depends_on = [
    aws_route.r_primary
  ]
}

# Create a route
resource "aws_route" "r_secondary" {
  route_table_id            = data.aws_route_table.rt_secondary.id
  destination_cidr_block    = "192.168.0.0/22"
  vpc_peering_connection_id = aws_vpc_peering_connection.vpcconnection.id
  depends_on = [
    data.aws_route_table.rt_secondary
  ]
}
