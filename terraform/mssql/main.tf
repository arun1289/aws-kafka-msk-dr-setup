provider "aws" {
  region = var.primary_region
}

provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
}

data "aws_vpc" "primary_vpc" {
  provider   = aws.primary
  cidr_block = var.primary_vpc
}

data "aws_availability_zones" "azs" {
  provider = aws.primary
  state    = "available"
}

data "aws_subnet" "subnet_az1" {
  provider          = aws.primary
  availability_zone = data.aws_availability_zones.azs.names[0]
  cidr_block        = var.primary_subnet_zone_a
  vpc_id            = data.aws_vpc.primary_vpc.id
}

data "aws_subnet" "subnet_az2" {
  provider          = aws.primary
  availability_zone = data.aws_availability_zones.azs.names[1]
  cidr_block        = var.primary_subnet_zone_b
  vpc_id            = data.aws_vpc.primary_vpc.id
}

data "aws_subnet" "subnet_az3" {
  provider          = aws.primary
  availability_zone = data.aws_availability_zones.azs.names[2]
  cidr_block        = var.primary_subnet_zone_c
  vpc_id            = data.aws_vpc.primary_vpc.id
}

resource "aws_instance" "mssql1" {
  provider      = aws.primary
  ami           = var.ami
  instance_type = var.instance_type

  network_interface {
    network_interface_id = var.network_interface_id
    device_index         = 0
  }
}
