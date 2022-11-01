data "aws_vpc" "primaryvpc" {
  provider = aws.ireland
  cidr_block = "10.31.188.0/22"
}

data "aws_availability_zones" "azs" {
  state = "available"
}

data "aws_subnet" "subnet_az1" {
  availability_zone = data.aws_availability_zones.azs.names[0]
  cidr_block        = "10.31.188.0/24"
  vpc_id            = data.aws_vpc.primaryvpc.id
}

data "aws_subnet" "subnet_az2" {
  availability_zone = data.aws_availability_zones.azs.names[1]
  cidr_block        = "10.31.189.0/24"
  vpc_id            = data.aws_vpc.primaryvpc.id
}

data "aws_subnet" "subnet_az3" {
  availability_zone = data.aws_availability_zones.azs.names[2]
  cidr_block        = "10.31.190.0/24"
  vpc_id            = data.aws_vpc.primaryvpc.id
}

resource "aws_security_group" "sg" {
  vpc_id                 = data.aws_vpc.primaryvpc.id
  revoke_rules_on_delete = true
  ingress {
    description = "TLS from VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "primaryvpcsecurity_mskcluster"
  }
  depends_on = [
    data.aws_vpc.primaryvpc
  ]
}

resource "aws_kms_key" "kms" {
  description = "primarykafkacluster"
}

resource "aws_cloudwatch_log_group" "test" {
  name = "msk_broker_logs"
}


resource "aws_msk_cluster" "primarykafkacluster" {
  cluster_name           = "o2-msk-primary"
  kafka_version          = "3.2.0"
  number_of_broker_nodes = 3

  broker_node_group_info {
    instance_type  = "kafka.m5.large"
    client_subnets = [
      data.aws_subnet.subnet_az1.id,
      data.aws_subnet.subnet_az2.id,
      data.aws_subnet.subnet_az3.id,
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
    sasl {
      iam   = true
      scram = true
    }
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
    }
  }

  tags = {
    Name        = "o2-msk-primary"
    Environment = "non-prod"
  }
}

output "zookeeper_connect_string" {
  value = aws_msk_cluster.primarykafkacluster.zookeeper_connect_string
}

output "bootstrap_brokers_tls" {
  description = "TLS connection host:port pairs"
  value       = aws_msk_cluster.primarykafkacluster.bootstrap_brokers
}