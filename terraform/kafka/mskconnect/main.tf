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

provider "aws" {
alias = "ireland"
 region = "eu-west-1"

}

data "aws_caller_identity" "accountdetails" {
  
}

data "aws_vpc" "secondaryvpc" {
  cidr_block = "10.0.0.0/16"
  }

data "aws_vpc" "primaryvpc" {
  provider = aws.ireland
cidr_block = "192.168.0.0/22"
}

data "aws_availability_zones" "azs" {
  state = "available"
}

data "aws_subnet" "subnet_az1" {
  availability_zone = data.aws_availability_zones.azs.names[0]
  cidr_block        = "10.0.0.0/24"
  vpc_id            = data.aws_vpc.secondaryvpc.id
}

data "aws_subnet" "subnet_az2" {
  availability_zone = data.aws_availability_zones.azs.names[1]
  cidr_block        = "10.0.1.0/24"
  vpc_id            = data.aws_vpc.secondaryvpc.id
}

data "aws_subnet" "subnet_az3" {
  availability_zone = data.aws_availability_zones.azs.names[2]
  cidr_block        = "10.0.2.0/24"
  vpc_id            = data.aws_vpc.secondaryvpc.id
}

data "aws_msk_cluster" "secondarykafkacluster" {
  cluster_name           = "secondarykafkacluster"
}

data "aws_msk_cluster" "primarykafkacluster" {
  provider = aws.ireland
  cluster_name           = "primarykafkacluster"
}

data "aws_iam_role" "MSKConnectMirrorRole" {
  name = "MSKConnectMirror"
}

resource "aws_security_group" "sg" {
  vpc_id = data.aws_vpc.secondaryvpc.id
  ingress {
    description      = "TLS from VPC"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    
    cidr_blocks      = ["0.0.0.0/0"]
    }
  egress {
    description      = "TLS from VPC"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    
    cidr_blocks      = ["0.0.0.0/0"]
    }
}

resource "aws_s3_bucket" "mm2bucket" {
  bucket = "mm2bucketmm2zipmskconnect"
  force_destroy = true
}

resource "aws_s3_object" "mm2object" {
  bucket = "mm2bucketmm2zipmskconnect"
  key    = "connect-api-2.7.1.jar"
  source = "connect-api-2.7.1.jar"
    etag = filemd5("/connect-api-2.7.1.jar")
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
"connector.class"="org.apache.kafka.connect.mirror.MirrorSourceConnector"
"target.cluster.alias"="target"
"sync.topic.acls.enabled"="false"
"tasks.max"=1
"topics"=".*"
"groups"=".*"
"emit.checkpoints.interval.seconds" = 1
"source.cluster.alias"="source"
"source.bootstrap.servers"=data.aws_msk_cluster.primarykafkacluster.bootstrap_brokers
"target.bootstrap.servers"=data.aws_msk_cluster.secondarykafkacluster.bootstrap_brokers
"emit.heartbeats.interval.seconds"=1
"value.converter"="org.apache.kafka.connect.converters.ByteArrayConverter"
"key.converter"="org.apache.kafka.connect.converters.ByteArrayConverter"
}

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = data.aws_msk_cluster.secondarykafkacluster.bootstrap_brokers

      vpc {
        security_groups = [aws_security_group.sg.id]
        subnets         = [data.aws_subnet.subnet_az1.id,
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
      enabled = true
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
"connector.class"="org.apache.kafka.connect.mirror.MirrorCheckpointConnector"
"target.cluster.alias"="target"
"sync.topic.acls.enabled"="false"
"tasks.max"=1
"topics"=".*"
"groups"=".*"
"emit.checkpoints.interval.seconds" = 1
"source.cluster.alias"="source"
"source.bootstrap.servers"=data.aws_msk_cluster.primarykafkacluster.bootstrap_brokers
"target.bootstrap.servers"=data.aws_msk_cluster.secondarykafkacluster.bootstrap_brokers
"emit.heartbeats.interval.seconds"=1
"value.converter"="org.apache.kafka.connect.converters.ByteArrayConverter"
"key.converter"="org.apache.kafka.connect.converters.ByteArrayConverter"
}

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = data.aws_msk_cluster.secondarykafkacluster.bootstrap_brokers

      vpc {
        security_groups = [aws_security_group.sg.id]
        subnets         = [data.aws_subnet.subnet_az1.id,
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
      enabled = true
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
"connector.class"="org.apache.kafka.connect.mirror.MirrorHeartbeatConnector"
"target.cluster.alias"="target"
"sync.topic.acls.enabled"="false"
"tasks.max"=1
"topics"=".*"
"groups"=".*"
"emit.checkpoints.interval.seconds" = 1
"source.cluster.alias"="source"
"source.bootstrap.servers"=data.aws_msk_cluster.primarykafkacluster.bootstrap_brokers
"target.bootstrap.servers"=data.aws_msk_cluster.secondarykafkacluster.bootstrap_brokers
"emit.heartbeats.interval.seconds"=1
"value.converter"="org.apache.kafka.connect.converters.ByteArrayConverter"
"key.converter"="org.apache.kafka.connect.converters.ByteArrayConverter"
}

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = data.aws_msk_cluster.secondarykafkacluster.bootstrap_brokers

      vpc {
        security_groups = [aws_security_group.sg.id]
        subnets         = [data.aws_subnet.subnet_az1.id,
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
      enabled = true
      log_group = aws_cloudwatch_log_group.mskconnect_MirrorHeartbeatConnector_logs.name
    }
  }
}
  service_execution_role_arn = data.aws_caller_identity.accountdetails.arn
  depends_on = [
    aws_mskconnect_custom_plugin.example
  ]
}

