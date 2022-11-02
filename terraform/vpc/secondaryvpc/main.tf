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
  region  = "eu-west-2"
}


resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support = true
      tags = {
    Name = "secondaryvpc_mskcluster"
  }
}

data "aws_availability_zones" "azs" {
  state = "available"
}

resource "aws_subnet" "subnet_az1" {
  availability_zone = data.aws_availability_zones.azs.names[0]
  cidr_block        = "10.0.0.0/24"
  vpc_id            = aws_vpc.vpc.id
   tags = {
    Name = "secondaryvpcsubnet1_mskcluster"
  }
    depends_on = [
    aws_vpc.vpc
  ]
}

resource "aws_subnet" "subnet_az2" {
  availability_zone = data.aws_availability_zones.azs.names[1]
  cidr_block        = "10.0.1.0/24"
  vpc_id            = aws_vpc.vpc.id
     tags = {
    Name = "secondaryvpcsubnet2_mskcluster"
  }
    depends_on = [
    aws_vpc.vpc
  ]
}

resource "aws_subnet" "subnet_az3" {
  availability_zone = data.aws_availability_zones.azs.names[2]
  cidr_block        = "10.0.2.0/24"
  vpc_id            = aws_vpc.vpc.id
     tags = {
    Name = "secondaryvpcsubnet3_mskcluster"
  }
    depends_on = [
    aws_vpc.vpc
  ]
}

resource "aws_subnet" "subnet_az4" {
  availability_zone = data.aws_availability_zones.azs.names[2]
  cidr_block        = "10.0.3.0/24"
  vpc_id            = aws_vpc.vpc.id
  map_public_ip_on_launch = true
     tags = {
    Name = "secondaryvpcsubnet4_mskcluster"
  }
    depends_on = [
    aws_vpc.vpc
  ]
}
