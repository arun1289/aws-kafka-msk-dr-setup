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
  region  = "eu-west-1"
}


resource "aws_vpc" "vpc" {
  cidr_block = "192.168.0.0/22"
  enable_dns_hostnames = true
  enable_dns_support = true
    tags = {
    Name = "primaryvpc_mskcluster"
  }
  }

data "aws_availability_zones" "azs" {
  state = "available"
}


resource "aws_subnet" "subnet_az1" {
  availability_zone = data.aws_availability_zones.azs.names[0]
  cidr_block        = "192.168.0.0/24"
  vpc_id            = aws_vpc.vpc.id
  depends_on = [
    aws_vpc.vpc
  ]
   tags = {
    Name = "primaryvpcsubnet1_mskcluster"
  }
}

resource "aws_subnet" "subnet_az2" {
  availability_zone = data.aws_availability_zones.azs.names[1]
  cidr_block        = "192.168.1.0/24"
  vpc_id            = aws_vpc.vpc.id
    depends_on = [
    aws_vpc.vpc
  ]
     tags = {
    Name = "primaryvpcsubnet2_mskcluster"
  }
}

resource "aws_subnet" "subnet_az3" {
  availability_zone = data.aws_availability_zones.azs.names[2]
  cidr_block        = "192.168.2.0/24"
  vpc_id            = aws_vpc.vpc.id
    depends_on = [
    aws_vpc.vpc
  ]
     tags = {
    Name = "primaryvpcsubnet3_mskcluster"
  }
}

resource "aws_subnet" "subnet_az4" {
  availability_zone = data.aws_availability_zones.azs.names[2]
  cidr_block        = "192.168.3.0/24"
  map_public_ip_on_launch = true
  vpc_id            = aws_vpc.vpc.id
    depends_on = [
    aws_vpc.vpc
  ]
     tags = {
    Name = "primaryvpcsubnet4_mskcluster"
  }
}
