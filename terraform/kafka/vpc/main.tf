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

resource "aws_vpc" "secondaryvpc" {
    cidr_block = "192.168.0.0/22"
}

resource "aws_vpc" "primaryvpc" {
   cidr_block = "192.168.0.0/22"
}

resource "aws_vpc_peering_connection" "vpcconnection" {
  peer_vpc_id   = aws_vpc.primaryvpc.id
  vpc_id        = aws_vpc.secondaryvpc.id
  peer_region   = "us-east-1"
  auto_accept   = true
    tags = {
    Side = "Requester"
  }
}

resource "aws_vpc_peering_connection_accepter" "peer" {
  vpc_peering_connection_id = "${aws_vpc_peering_connection.vpcconnection.id}"
  auto_accept               = true
    tags = {
    Side = "Accepter"
  }
}  