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

resource "aws_s3_bucket" "mm2bucket" {
  bucket = "mm2bucket"
}

resource "aws_s3_object" "mm2object" {
  bucket = aws_s3_bucket.mm2bucket.id
  key    = "mm2.zip"
  source = "mm2.zip"
}

resource "aws_mskconnect_custom_plugin" "example" {
  name         = "mm2-example"
  content_type = "ZIP"
  location {
    s3 {
      bucket_arn = aws_s3_bucket.mm2bucket.arn
      file_key   = aws_s3_object.mm2object.key
    }
  }
}