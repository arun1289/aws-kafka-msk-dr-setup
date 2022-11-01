terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
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
  alias  = "london"
  region = "eu-west-2"
}

provider "aws" {
  alias  = "ireland"
  region = "eu-west-1"
}

module "iam-role" {
  source = "./iamrole"
}

module "primary" {
  source = "./primary"
}

module "secondary" {
  source = "./secondary"
}

module "mskconnect" {
  source = "./mskconnect"
}