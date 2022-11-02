terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 2.7.0"
      configuration_aliases = [ aws.primary, aws.secondary ]
    }
  }
}

data "aws_vpc" "secondary_vpc" {
  provider = aws.secondary
  cidr_block = var.secondary_vpc
}

data "aws_vpc" "primary_vpc" {
  provider   = aws.primary
  cidr_block = var.primary_vpc
}

data "aws_availability_zones" "azs" {
  provider = aws.secondary
  state = "available"
}

data "aws_caller_identity" "accountdetails" {
  provider = aws.secondary
}

resource "aws_vpc_peering_connection" "vpcconnection" {
  provider = aws.secondary
  peer_owner_id = data.aws_caller_identity.accountdetails.account_id
  peer_vpc_id   = data.aws_vpc.primary_vpc.id
  vpc_id        = data.aws_vpc.secondary_vpc.id
  peer_region   = var.primary_region
  auto_accept   = false
  tags          = {
    Side = "Requester"
  }
}

resource "aws_vpc_peering_connection_accepter" "peer" {
  provider                  = aws.primary
  vpc_peering_connection_id = "${aws_vpc_peering_connection.vpcconnection.id}"
  auto_accept               = true
  tags                      = {
    Side = "Accepter"
  }
  depends_on = [
    aws_vpc_peering_connection.vpcconnection
  ]
}

# Create a route table
data "aws_route_table" "rt_primary" {
  provider   = aws.primary
  vpc_id     = data.aws_vpc.primary_vpc.id
  depends_on = [
    aws_vpc_peering_connection_accepter.peer
  ]
}

# Create a route
resource "aws_route" "r_primary" {
  provider                  = aws.primary
  route_table_id            = data.aws_route_table.rt_primary.id
  destination_cidr_block    = var.primary_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.vpcconnection.id
  depends_on                = [
    data.aws_route_table.rt_primary
  ]
}

# Create a route table
data "aws_route_table" "rt_secondary" {
  provider = aws.secondary
  vpc_id     = data.aws_vpc.secondary_vpc.id
  depends_on = [
    aws_route.r_primary
  ]
}

# Create a route
resource "aws_route" "r_secondary" {
  provider = aws.secondary
  route_table_id            = data.aws_route_table.rt_secondary.id
  destination_cidr_block    = var.secondary_vpc
  vpc_peering_connection_id = aws_vpc_peering_connection.vpcconnection.id
  depends_on                = [
    data.aws_route_table.rt_secondary
  ]
}
