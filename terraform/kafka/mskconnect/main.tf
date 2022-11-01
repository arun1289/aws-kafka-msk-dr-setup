
provider "aws" {
    alias = "london"
    region = "us-west-2"
}

provider "aws" {
  alias = "ireland"
  region = "eu-west-1"
}

data "aws_caller_identity" "accountdetails" {
  
}

data "aws_vpc" "secondaryvpc" {
  provider   = aws.london
  cidr_block = "172.31.0.0/16"
}

data "aws_vpc" "primaryvpc" {
  provider   = aws.ireland
  cidr_block = "10.31.188.0/22"
}

data "aws_availability_zones" "azs" {
  provider = aws.ireland
  state    = "available"
}

data "aws_subnet" "subnet_az1" {
  provider          = aws.london
  availability_zone = data.aws_availability_zones.azs.names[0]
  cidr_block        = "172.31.16.0/20"
  vpc_id            = data.aws_vpc.secondaryvpc.id
}

data "aws_subnet" "subnet_az2" {
  provider          = aws.london
  availability_zone = data.aws_availability_zones.azs.names[1]
  cidr_block        = "172.31.32.0/20"
  vpc_id            = data.aws_vpc.secondaryvpc.id
}

data "aws_subnet" "subnet_az3" {
  provider          = aws.london
  availability_zone = data.aws_availability_zones.azs.names[2]
  cidr_block        = "172.31.0.0/20"
  vpc_id            = data.aws_vpc.secondaryvpc.id
}

data "aws_msk_cluster" "secondarykafkacluster" {
  provider     = aws.london
  cluster_name = "secondarykafkacluster"
}

data "aws_msk_cluster" "primarykafkacluster" {
  provider     = aws.ireland
  cluster_name = "primarykafkacluster"
}

data "aws_iam_role" "MSKConnectMirrorRole" {
  name = "MSKConnectMirror"
}

resource "aws_security_group" "sg" {
  provider = aws.london
  vpc_id   = data.aws_vpc.secondaryvpc.id
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
  provider = aws.london
  name     = "mskconnect_MirrorSourceConnector_logs"
}

resource "aws_cloudwatch_log_group" "mskconnect_MirrorCheckpointConnector_logs" {
  provider = aws.london
  name     = "mskconnect_MirrorCheckpointConnector_logs"
}
resource "aws_cloudwatch_log_group" "mskconnect_MirrorHeartbeatConnector_logs" {
  provider = aws.london
  name     = "mskconnect_MirrorHeartbeatConnector_logs"
}

resource "aws_mskconnect_custom_plugin" "example" {
  provider     = aws.london
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
  provider = aws.london
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

  service_execution_role_arn = data.aws_caller_identity.accountdetails.arn
  depends_on = [
    aws_mskconnect_custom_plugin.example
  ]
}


resource "aws_mskconnect_connector" "MirrorCheckpointConnector" {
  provider = aws.london
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
  
  service_execution_role_arn = data.aws_caller_identity.accountdetails.arn
  depends_on = [
    aws_mskconnect_custom_plugin.example
  ]
}

resource "aws_mskconnect_connector" "MirrorHeartbeatConnector" {
  provider = aws.london
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
 
 
  service_execution_role_arn = data.aws_caller_identity.accountdetails.arn
  depends_on = [
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

