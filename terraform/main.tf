terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
      configuration_aliases = [ aws.primary, aws.secondary ]
    }
  }


  backend "s3" {
    bucket = "non-prod-o2-terraform-state"
    key = "app-state"
    region = "eu-west-1"
    dynamodb_table = "o2-terraform-lock-state"
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  alias = "primary"
  region = "eu-west-1"
}


provider "aws" {
  alias = "secondary"
  region = "eu-west-2"
}

module "iam-role" {
  source = "./iamrole"
  providers = {
    aws = aws.primary
  }
}

module "primary" {
  source = "./kafka/primary"
  providers = {
    aws = aws.primary
  }
  primary_region = var.primary_region
  primary_vpc = var.primary_vpc
  primary_subnet_zone_a = var.primary_subnet_zone_a
  primary_subnet_zone_b = var.primary_subnet_zone_b
  primary_subnet_zone_c = var.primary_subnet_zone_c
}

module "secondary" {
  source = "./kafka/secondary"
  providers = {
    aws = aws.secondary
  }

  secondary_region = var.secondary_region
  secondary_vpc = var.secondary_vpc
  secondary_subnet_zone_a = var.secondary_subnet_zone_a
  secondary_subnet_zone_b = var.secondary_subnet_zone_b
  secondary_subnet_zone_c = var.secondary_subnet_zone_c
}

module "mssql" {
  source = "./mssql"
  providers = {
    aws.primary = aws.primary
    aws.secondary = aws.secondary
  }

  primary_region = var.primary_region
  primary_vpc = var.primary_vpc
  primary_subnet_zone_a = var.primary_subnet_zone_a
  primary_subnet_zone_b = var.primary_subnet_zone_b
  primary_subnet_zone_c = var.primary_subnet_zone_c

  secondary_region = var.secondary_region
  secondary_vpc = var.secondary_vpc
  secondary_subnet_zone_a = var.secondary_subnet_zone_a
  secondary_subnet_zone_b = var.secondary_subnet_zone_b
  secondary_subnet_zone_c = var.secondary_subnet_zone_c
}

module "mskconnect" {
  source = "./kafka/mskconnect"
  providers = {
    aws.primary = aws.primary
    aws.secondary = aws.secondary
  }

  primary_region = var.primary_region
  primary_vpc = var.primary_vpc
  primary_subnet_zone_a = var.primary_subnet_zone_a
  primary_subnet_zone_b = var.primary_subnet_zone_b
  primary_subnet_zone_c = var.primary_subnet_zone_c

  secondary_region = var.secondary_region
  secondary_vpc = var.secondary_vpc
  secondary_subnet_zone_a = var.secondary_subnet_zone_a
  secondary_subnet_zone_b = var.secondary_subnet_zone_b
  secondary_subnet_zone_c = var.secondary_subnet_zone_c

  depends_on = [module.primary, module.secondary]
}