terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 2.7.0"
    }
  }
}

data "aws_vpc" "vpc" {
  cidr_block = var.vpc
}

data "aws_availability_zones" "azs" {
  state = "available"
}

data "aws_subnet" "subnet_az1" {
  availability_zone = data.aws_availability_zones.azs.names[0]
  cidr_block        = var.subnet_zone_a
  vpc_id            = data.aws_vpc.vpc.id
}

data "aws_subnet" "subnet_az2" {
  availability_zone = data.aws_availability_zones.azs.names[1]
  cidr_block        = var.subnet_zone_b
  vpc_id            = data.aws_vpc.vpc.id
}

data "aws_subnet" "subnet_az3" {
  availability_zone = data.aws_availability_zones.azs.names[2]
  cidr_block        = var.subnet_zone_c
  vpc_id            = data.aws_vpc.vpc.id
}


resource "aws_instance" "mssql_server" {
  ami               = var.ami
  instance_type     = var.instance_type
  availability_zone = data.aws_subnet.subnet_az1.availability_zone
  subnet_id         = data.aws_subnet.subnet_az1.id

  root_block_device {
    volume_size = 128
    volume_type = "gp3"
    encrypted   = false
  }

  key_name = "o2"

  tags = {
    Name = "Sql server 2017"
  }
}

resource "aws_ebs_volume" "ebs_drive_sql_drive" {
  availability_zone = data.aws_subnet.subnet_az1.availability_zone
  type              = "gp3"
  iops              = 7500
  throughput        = 400
  size              = 512
}

resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.ebs_drive_sql_drive.id
  instance_id = aws_instance.mssql_server.id
}



