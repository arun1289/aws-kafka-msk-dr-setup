terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 2.7.0"
      configuration_aliases = [ aws.primary, aws.secondary ]
    }
  }
}

data "aws_caller_identity" "accountdetails" {
  provider = aws.secondary
}

data "aws_vpc" "secondary_vpc" {
  provider = aws.secondary
  cidr_block = var.secondary_vpc
}

data "aws_vpc" "primary_vpc" {
  provider   = aws.primary
  cidr_block = var.primary_vpc
}

data "aws_availability_zones" "azs" {
  provider = aws.secondary
  state    = "available"
}

data "aws_subnet" "subnet_az1" {
  provider = aws.secondary
  availability_zone = data.aws_availability_zones.azs.names[0]
  cidr_block        = var.secondary_subnet_zone_a
  vpc_id            = data.aws_vpc.secondary_vpc.id
}

data "aws_subnet" "subnet_az2" {
  provider = aws.secondary
  availability_zone = data.aws_availability_zones.azs.names[1]
  cidr_block        = var.secondary_subnet_zone_b
  vpc_id            = data.aws_vpc.secondary_vpc.id
}

data "aws_subnet" "subnet_az3" {
  provider = aws.secondary
  availability_zone = data.aws_availability_zones.azs.names[2]
  cidr_block        = var.secondary_subnet_zone_c
  vpc_id            = data.aws_vpc.secondary_vpc.id
}

data "aws_msk_cluster" "secondarykafkacluster" {
  provider = aws.secondary
  cluster_name = "o2-msk-secondary"
}

data "aws_msk_cluster" "primarykafkacluster" {
  provider     = aws.primary
  cluster_name = "o2-msk-primary"
}

data "aws_iam_role" "MSKConnectMirrorRole" {
  provider = aws.secondary
  name = "MSKConnectMirror"
}

resource "aws_security_group" "sg" {
  provider = aws.secondary
  vpc_id   = data.aws_vpc.secondary_vpc.id
  ingress {
    description = "TLS from VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"

    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "TLS from VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"

    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_s3_bucket" "mm2bucket" {
  provider = aws.secondary
  bucket        = "mm2bucketmm2zipmskconnect"
  force_destroy = true
}

resource "aws_s3_object" "mm2object" {
  provider = aws.secondary
  bucket     = "mm2bucketmm2zipmskconnect"
  key        = "connect-api-2.7.1.jar"
  source     = "./kafka/mskconnect/mm2/connect-api-2.7.1.jar"
  etag       = filemd5("./kafka/mskconnect/mm2/connect-api-2.7.1.jar")
  depends_on = [
    aws_s3_bucket.mm2bucket
  ]
}

resource "aws_cloudwatch_log_group" "mskconnect_MirrorSourceConnector_logs" {
  provider = aws.secondary
  name     = "mskconnect_MirrorSourceConnector_logs"
}

resource "aws_cloudwatch_log_group" "mskconnect_MirrorCheckpointConnector_logs" {
  provider = aws.secondary
  name     = "mskconnect_MirrorCheckpointConnector_logs"
}
resource "aws_cloudwatch_log_group" "mskconnect_MirrorHeartbeatConnector_logs" {
  name     = "mskconnect_MirrorHeartbeatConnector_logs"
}

resource "aws_mskconnect_custom_plugin" "example" {
  provider = aws.secondary
  name         = "MSKConnectPlugin"
  content_type = "ZIP"
  location {
    s3 {
      bucket_arn = aws_s3_bucket.mm2bucket.arn
      file_key   = aws_s3_object.mm2object.key
    }
  }
}


resource "aws_mskconnect_connector" "MirrorSourceConnector" {
  provider = aws.secondary
  name     = "MirrorSourceConnector"

  kafkaconnect_version = "2.7.1"

  capacity {
    autoscaling {
      mcu_count        = 1
      min_worker_count = 1
      max_worker_count = 2

      scale_in_policy {
        cpu_utilization_percentage = 20
      }

      scale_out_policy {
        cpu_utilization_percentage = 80
      }
    }
  }

  connector_configuration = {
    "connector.class"                   = "org.apache.kafka.connect.mirror.MirrorSourceConnector"
    "target.cluster.alias"              = "target"
    "sync.topic.acls.enabled"           = "false"
    "tasks.max"                         = 1
    "topics"                            = ".*"
    "groups"                            = ".*"
    "emit.checkpoints.interval.seconds" = 1
    "source.cluster.alias"              = "source"
    "source.cluster.bootstrap.servers"  = "${data.aws_msk_cluster.primarykafkacluster.bootstrap_brokers}"
    "target.cluster.bootstrap.servers"  = "${data.aws_msk_cluster.secondarykafkacluster.bootstrap_brokers}"

    "emit.heartbeats.interval.seconds" = 1
    "value.converter"                  = "org.apache.kafka.connect.converters.ByteArrayConverter"
    "key.converter"                    = "org.apache.kafka.connect.converters.ByteArrayConverter"
  }

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = "${data.aws_msk_cluster.secondarykafkacluster.bootstrap_brokers}"

      vpc {
        security_groups = [aws_security_group.sg.id]
        subnets         = [
          data.aws_subnet.subnet_az1.id,
          data.aws_subnet.subnet_az2.id,
          data.aws_subnet.subnet_az3.id,
        ]
      }
    }
  }

  kafka_cluster_client_authentication {
    authentication_type = "NONE"
  }

  kafka_cluster_encryption_in_transit {
    encryption_type = "PLAINTEXT"
  }

  plugin {
    custom_plugin {
      arn      = aws_mskconnect_custom_plugin.example.arn
      revision = aws_mskconnect_custom_plugin.example.latest_revision
    }
  }

  log_delivery {
    worker_log_delivery {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.mskconnect_MirrorSourceConnector_logs.name
      }
    }
  }

  service_execution_role_arn = data.aws_caller_identity.accountdetails.arn
  depends_on                 = [
    aws_mskconnect_custom_plugin.example
  ]
}


resource "aws_mskconnect_connector" "MirrorCheckpointConnector" {
  provider = aws.secondary
  name     = "MirrorCheckpointConnector"

  kafkaconnect_version = "2.7.1"

  capacity {
    autoscaling {
      mcu_count        = 1
      min_worker_count = 1
      max_worker_count = 2

      scale_in_policy {
        cpu_utilization_percentage = 20
      }

      scale_out_policy {
        cpu_utilization_percentage = 80
      }
    }
  }

  connector_configuration = {
    "connector.class"                   = "org.apache.kafka.connect.mirror.MirrorCheckpointConnector"
    "target.cluster.alias"              = "target"
    "sync.topic.acls.enabled"           = "false"
    "tasks.max"                         = 1
    "topics"                            = ".*"
    "groups"                            = ".*"
    "emit.checkpoints.interval.seconds" = 1
    "source.cluster.alias"              = "source"
    "source.cluster.bootstrap.servers"  = "${data.aws_msk_cluster.primarykafkacluster.bootstrap_brokers}"
    "target.cluster.bootstrap.servers"  = "${data.aws_msk_cluster.secondarykafkacluster.bootstrap_brokers}"
    "emit.heartbeats.interval.seconds"  = 1
    "value.converter"                   = "org.apache.kafka.connect.converters.ByteArrayConverter"
    "key.converter"                     = "org.apache.kafka.connect.converters.ByteArrayConverter"
  }

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = "${data.aws_msk_cluster.secondarykafkacluster.bootstrap_brokers}"

      vpc {
        security_groups = [aws_security_group.sg.id]
        subnets         = [
          data.aws_subnet.subnet_az1.id,
          data.aws_subnet.subnet_az2.id,
          data.aws_subnet.subnet_az3.id,
        ]
      }
    }
  }

  kafka_cluster_client_authentication {
    authentication_type = "NONE"
  }

  kafka_cluster_encryption_in_transit {
    encryption_type = "PLAINTEXT"
  }

  plugin {
    custom_plugin {
      arn      = aws_mskconnect_custom_plugin.example.arn
      revision = aws_mskconnect_custom_plugin.example.latest_revision
    }
  }
  log_delivery {
    worker_log_delivery {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.mskconnect_MirrorCheckpointConnector_logs.name
      }
    }
  }

  service_execution_role_arn = data.aws_caller_identity.accountdetails.arn
  depends_on                 = [
    aws_mskconnect_custom_plugin.example
  ]
}

resource "aws_mskconnect_connector" "MirrorHeartbeatConnector" {
  provider = aws.secondary
  name     = "MirrorHeartbeatConnector"

  kafkaconnect_version = "2.7.1"

  capacity {
    autoscaling {
      mcu_count        = 1
      min_worker_count = 1
      max_worker_count = 2

      scale_in_policy {
        cpu_utilization_percentage = 20
      }

      scale_out_policy {
        cpu_utilization_percentage = 80
      }
    }
  }

  connector_configuration = {
    "connector.class"                   = "org.apache.kafka.connect.mirror.MirrorHeartbeatConnector"
    "target.cluster.alias"              = "target"
    "sync.topic.acls.enabled"           = "false"
    "tasks.max"                         = 1
    "topics"                            = ".*"
    "groups"                            = ".*"
    "emit.checkpoints.interval.seconds" = 1
    "source.cluster.alias"              = "source"
    "source.cluster.bootstrap.servers"  = "${data.aws_msk_cluster.primarykafkacluster.bootstrap_brokers}"
    "target.cluster.bootstrap.servers"  = "${data.aws_msk_cluster.secondarykafkacluster.bootstrap_brokers}"
    "emit.heartbeats.interval.seconds"  = 1
    "value.converter"                   = "org.apache.kafka.connect.converters.ByteArrayConverter"
    "key.converter"                     = "org.apache.kafka.connect.converters.ByteArrayConverter"
  }

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = "${data.aws_msk_cluster.secondarykafkacluster.bootstrap_brokers}"

      vpc {
        security_groups = [aws_security_group.sg.id]
        subnets         = [
          data.aws_subnet.subnet_az1.id,
          data.aws_subnet.subnet_az2.id,
          data.aws_subnet.subnet_az3.id,
        ]
      }
    }
  }

  kafka_cluster_client_authentication {
    authentication_type = "NONE"
  }

  kafka_cluster_encryption_in_transit {
    encryption_type = "PLAINTEXT"
  }

  plugin {
    custom_plugin {
      arn      = aws_mskconnect_custom_plugin.example.arn
      revision = aws_mskconnect_custom_plugin.example.latest_revision
    }
  }
  log_delivery {
    worker_log_delivery {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.mskconnect_MirrorHeartbeatConnector_logs.name
      }
    }
  }


  service_execution_role_arn = data.aws_caller_identity.accountdetails.arn
  depends_on                 = [
    aws_mskconnect_custom_plugin.example
  ]
}

output "account_id" {
  value = data.aws_caller_identity.accountdetails.account_id
}

output "caller_user" {
  value = data.aws_caller_identity.accountdetails.user_id
}

output "caller_arn" {
  value = data.aws_caller_identity.accountdetails.arn
}

