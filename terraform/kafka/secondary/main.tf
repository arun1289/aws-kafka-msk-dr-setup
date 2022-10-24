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
  region  = "us-west-2"
}


resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support = true
      tags = {
    Name = "secondaryvpc_mskcluster"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.vpc.id
 
  tags = {
    Name = "secondary_internet_gateway"
  }
  depends_on = [
    aws_vpc.vpc
  ]
}


data "aws_route_table" "secondaryvpc_mskcluster_routetable" {
  vpc_id = aws_vpc.vpc.id
}
data "aws_availability_zones" "azs" {
  state = "available"
}

resource "aws_route" "secondaryvpc_mskcluster_route_gatewaytraffic" {
  route_table_id            = data.aws_route_table.secondaryvpc_mskcluster_routetable.id
  destination_cidr_block    = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.gw.id
}

resource "aws_subnet" "subnet_az1" {
  availability_zone = data.aws_availability_zones.azs.names[0]
  cidr_block        = "10.0.0.0/24"
  vpc_id            = aws_vpc.vpc.id
  map_public_ip_on_launch = true
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

resource "aws_security_group" "sg" {
  vpc_id = aws_vpc.vpc.id
  revoke_rules_on_delete = true
   ingress {
    description      = "TLS from VPC"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    
    cidr_blocks      = ["0.0.0.0/0"]
    }
  }

resource "aws_kms_key" "kms" {
  description = "secondarykafkacluster"
}

resource "aws_cloudwatch_log_group" "test" {
  name = "msk_broker_logs"
}

resource "aws_s3_bucket" "bucket" {
  bucket = "msk-broker-logs-bucket-coremont-sandbox-secondary"
    force_destroy = true
}

resource "aws_s3_bucket_acl" "bucket_acl" {
  bucket = aws_s3_bucket.bucket.id
  acl    = "private"
}

resource "aws_iam_role" "firehose_role" {
  name = "firehose_test_role_secondary"

  assume_role_policy = <<EOF
{
"Version": "2012-10-17",
"Statement": [
  {
    "Action": "sts:AssumeRole",
    "Principal": {
      "Service": "firehose.amazonaws.com"
    },
    "Effect": "Allow",
    "Sid": ""
  }
  ]
}
EOF
}

resource "aws_kinesis_firehose_delivery_stream" "test_stream" {
  name        = "terraform-kinesis-firehose-msk-broker-logs-stream"
  destination = "s3"

  s3_configuration {
    role_arn   = aws_iam_role.firehose_role.arn
    bucket_arn = aws_s3_bucket.bucket.arn
  }

  tags = {
    LogDeliveryEnabled = "placeholder"
  }

  lifecycle {
    ignore_changes = [
      tags["LogDeliveryEnabled"],
    ]
  }
}

resource "aws_msk_cluster" "secondarykafkacluster" {
  cluster_name           = "secondarykafkacluster"
  kafka_version          = "3.2.0"
  number_of_broker_nodes = 3
 
  broker_node_group_info {
    instance_type = "kafka.m5.large"
    client_subnets = [
      aws_subnet.subnet_az1.id,
      aws_subnet.subnet_az2.id,
      aws_subnet.subnet_az3.id,
    ]
    storage_info {
      ebs_storage_info {
        volume_size = 1000
      }
    }
    security_groups = [aws_security_group.sg.id]
  }

  encryption_info {
    encryption_at_rest_kms_key_arn = aws_kms_key.kms.arn
    encryption_in_transit {
      client_broker = "TLS_PLAINTEXT"
    }
  }

client_authentication {
  unauthenticated = true
}

  open_monitoring {
    prometheus {
      jmx_exporter {
        enabled_in_broker = true
      }
      node_exporter {
        enabled_in_broker = true
      }
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.test.name
      }
      firehose {
        enabled         = true
        delivery_stream = aws_kinesis_firehose_delivery_stream.test_stream.name
      }
      s3 {
        enabled = true
        bucket  = aws_s3_bucket.bucket.id
        prefix  = "logs/msk-"
      }
    }
  }

  tags = {
    foo = "bar"
  }
}

resource "aws_network_interface" "ani" {
  subnet_id   = aws_subnet.subnet_az1.id
   tags = {
    Name = "primary_network_interface"
  }
}

resource "aws_instance" "awskafkaclient" {
  ami           = "ami-005e54dee72cc1d00" # us-west-2
  instance_type = "t2.micro"
  network_interface {
    network_interface_id = aws_network_interface.ani.id
    device_index         = 0
  }

  credit_specification {
    cpu_credits = "unlimited"
  }
}
output "zookeeper_connect_string" {
  value = aws_msk_cluster.secondarykafkacluster.zookeeper_connect_string
}

output "bootstrap_brokers_tls" {
  description = "TLS connection host:port pairs"
  value       = aws_msk_cluster.secondarykafkacluster.bootstrap_brokers
}