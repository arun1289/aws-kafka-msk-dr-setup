data "aws_vpc" "secondaryvpc" {
  provider   = aws.london
  cidr_block = "172.31.0.0/16"
}

data "aws_vpc" "primaryvpc" {
  provider   = aws.ireland
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

data "aws_msk_cluster" "secondarykafkacluster" {
  cluster_name = "secondarykafkacluster"
}

data "aws_msk_cluster" "primarykafkacluster" {
  provider     = aws.ireland
  cluster_name = "primarykafkacluster"
}


resource "aws_security_group" "sg" {
  vpc_id = data.aws_vpc.secondaryvpc.id
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
  bucket        = "mm2bucketmm2zipmskconnect"
  force_destroy = true
}

resource "aws_s3_object" "mm2object" {
  bucket     = "mm2bucketmm2zipmskconnect"
  key        = "connect-api-2.7.1.jar"
  source     = "connect-api-2.7.1.jar"
  etag       = filemd5("/connect-api-2.7.1.jar")
  depends_on = [
    aws_s3_bucket.mm2bucket
  ]
}

resource "aws_cloudwatch_log_group" "mskconnect_MirrorSourceConnector_logs" {
  name = "mskconnect_MirrorSourceConnector_logs"
}

resource "aws_cloudwatch_log_group" "mskconnect_MirrorCheckpointConnector_logs" {
  name = "mskconnect_MirrorCheckpointConnector_logs"
}
resource "aws_cloudwatch_log_group" "mskconnect_MirrorHeartbeatConnector_logs" {
  name = "mskconnect_MirrorHeartbeatConnector_logs"
}

resource "aws_mskconnect_custom_plugin" "example" {
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
  name = "MirrorSourceConnector"

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
    "source.bootstrap.servers"          = data.aws_msk_cluster.primarykafkacluster.bootstrap_brokers
    "target.bootstrap.servers"          = data.aws_msk_cluster.secondarykafkacluster.bootstrap_brokers
    "emit.heartbeats.interval.seconds"  = 1
    "value.converter"                   = "org.apache.kafka.connect.converters.ByteArrayConverter"
    "key.converter"                     = "org.apache.kafka.connect.converters.ByteArrayConverter"
  }

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = data.aws_msk_cluster.secondarykafkacluster.bootstrap_brokers

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

  service_execution_role_arn = "arn:aws:iam::100828196990:role/MSKConnectMirror"
  depends_on                 = [
    aws_mskconnect_custom_plugin.example
  ]
}


resource "aws_mskconnect_connector" "MirrorCheckpointConnector" {
  name = "MirrorCheckpointConnector"

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
    "source.bootstrap.servers"          = data.aws_msk_cluster.primarykafkacluster.bootstrap_brokers
    "target.bootstrap.servers"          = data.aws_msk_cluster.secondarykafkacluster.bootstrap_brokers
    "emit.heartbeats.interval.seconds"  = 1
    "value.converter"                   = "org.apache.kafka.connect.converters.ByteArrayConverter"
    "key.converter"                     = "org.apache.kafka.connect.converters.ByteArrayConverter"
  }

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = data.aws_msk_cluster.secondarykafkacluster.bootstrap_brokers

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
  service_execution_role_arn = "arn:aws:iam::100828196990:role/MSKConnectMirror"
  depends_on                 = [
    aws_mskconnect_custom_plugin.example
  ]
}

resource "aws_mskconnect_connector" "MirrorHeartbeatConnector" {
  name = "MirrorHeartbeatConnector"

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
    "source.bootstrap.servers"          = data.aws_msk_cluster.primarykafkacluster.bootstrap_brokers
    "target.bootstrap.servers"          = data.aws_msk_cluster.secondarykafkacluster.bootstrap_brokers
    "emit.heartbeats.interval.seconds"  = 1
    "value.converter"                   = "org.apache.kafka.connect.converters.ByteArrayConverter"
    "key.converter"                     = "org.apache.kafka.connect.converters.ByteArrayConverter"
  }

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = data.aws_msk_cluster.secondarykafkacluster.bootstrap_brokers

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
  service_execution_role_arn = "arn:aws:iam::100828196990:role/MSKConnectMirror"
  depends_on                 = [
    aws_mskconnect_custom_plugin.example
  ]
}

