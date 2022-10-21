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

resource "aws_vpc" "secondaryvpc" {
    cidr_block = "10.0.0.0/22"
}

resource "aws_vpc" "primaryvpc" {
  provider = aws.ireland
   cidr_block = "192.168.0.0/22"
}

resource "aws_vpc_peering_connection" "vpcconnection" {
  peer_owner_id = "100828196990"
  peer_vpc_id   = aws_vpc.primaryvpc.id
  vpc_id        = aws_vpc.secondaryvpc.id
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
}  