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

resource "aws_vpc" "secondaryvpc" {
    cidr_block = "10.0.0.0/22"
}

resource "aws_vpc" "primaryvpc" {
  provider = aws.ireland
   cidr_block = "192.168.0.0/22"
}

data "aws_availability_zones" "azs" {
  state = "available"
}

resource "aws_subnet" "subnet_az1" {
  availability_zone = data.aws_availability_zones.azs.names[0]
  cidr_block        = "10.0.0.0/24"
  vpc_id            = aws_vpc.secondaryvpc.id
}

resource "aws_subnet" "subnet_az2" {
  availability_zone = data.aws_availability_zones.azs.names[1]
  cidr_block        = "10.0.1.0/24"
  vpc_id            = aws_vpc.secondaryvpc.id
}

resource "aws_subnet" "subnet_az3" {
  availability_zone = data.aws_availability_zones.azs.names[2]
  cidr_block        = "10.0.2.0/24"
  vpc_id            = aws_vpc.secondaryvpc.id
}

resource "aws_vpc_peering_connection" "vpcconnection" {
  peer_owner_id = "100828196990"
  peer_vpc_id   = aws_vpc.primaryvpc.id
  vpc_id        = aws_vpc.secondaryvpc.id
  peer_region   = "eu-west-1"
  auto_accept   = false
    tags = {
    Side = "Requester"
  }
}

resource "aws_vpc_peering_connection_accepter" "peer" {
  provider = aws.ireland
  vpc_peering_connection_id = "${aws_vpc_peering_connection.vpcconnection.id}"
  auto_accept               = true
    tags = {
    Side = "Accepter"
  }
}  

resource "aws_security_group" "sg" {
  vpc_id = aws_vpc.secondaryvpc.id
}

resource "aws_s3_bucket" "mm2bucket" {
  bucket = "mm2bucketmm2zipmskconnect"
  force_destroy = true
}

resource "aws_s3_object" "mm2object" {
  bucket = "mm2bucketmm2zipmskconnect"
  key    = "mm2.zip"
  source = "mm2.zip"
    etag = filemd5("/mm2/mm2.zip")
    depends_on = [
      aws_s3_bucket.mm2bucket
    ]
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
"tasks.max"="20"
"clusters"="source,target"
"source.cluster.alias"="source"
"target.cluster.alias"="target"
"source.cluster.bootstrap.servers"="b-1.primarykafkacluster.fai77k.c6.kafka.eu-west-1.amazonaws.com:9094,b-2.primarykafkacluster.fai77k.c6.kafka.eu-west-1.amazonaws.com:9094,b-3.primarykafkacluster.fai77k.c6.kafka.eu-west-1.amazonaws.com:9094"
"source.cluster.producer.sasl.client.callback.handler.class"="software.amazon.msk.auth.iam.IAMClientCallbackHandler"
"source.cluster.producer.security.protocol"="SASL_SSL"
"source.cluster.producer.sasl.mechanism"="AWS_MSK_IAM"
"source.cluster.producer.sasl.jaas.config"="software.amazon.msk.auth.iam.IAMLoginModule required awsRoleArn=\"arn:aws:iam::100828196990:user/org_arun_developer1\" awsDebugCreds=true;"
"source.cluster.consumer.sasl.client.callback.handler.class"="software.amazon.msk.auth.iam.IAMClientCallbackHandler"
"source.cluster.consumer.sasl.jaas.config"="software.amazon.msk.auth.iam.IAMLoginModule required awsRoleArn=\"arn:aws:iam::100828196990:user/org_arun_developer1\" awsDebugCreds=true;"
"source.cluster.consumer.security.protocol"="SASL_SSL"
"source.cluster.consumer.sasl.mechanism"="AWS_MSK_IAM"
"source.cluster.sasl.jaas.config"="software.amazon.msk.auth.iam.IAMLoginModule required awsRoleArn=\"arn:aws:iam::100828196990:user/org_arun_developer1\" awsDebugCreds=true;"
"source.cluster.sasl.mechanism"="AWS_MSK_IAM"
"source.cluster.security.protocol"="SASL_SSL"
"source.cluster.sasl.client.callback.handler.class"="software.amazon.msk.auth.iam.IAMClientCallbackHandler"
"target.cluster.bootstrap.servers"="b-1.secondarykafkacluster.wjy7cv.c10.kafka.us-west-2.amazonaws.com:9094,b-2.secondarykafkacluster.wjy7cv.c10.kafka.us-west-2.amazonaws.com:9094,b-3.secondarykafkacluster.wjy7cv.c10.kafka.us-west-2.amazonaws.com:9094"
"target.cluster.security.protocol"="SASL_SSL"
"target.cluster.sasl.jaas.config"="software.amazon.msk.auth.iam.IAMLoginModule required awsRoleArn=\"arn:aws:iam::100828196990:user/org_arun_developer1\" awsDebugCreds=true;"
"target.cluster.producer.sasl.mechanism"="AWS_MSK_IAM"
"target.cluster.producer.security.protocol"="SASL_SSL"
"target.cluster.producer.sasl.jaas.config"="software.amazon.msk.auth.iam.IAMLoginModule required awsRoleArn=\"arn:aws:iam::100828196990:user/org_arun_developer1\" awsDebugCreds=true;"
"target.cluster.producer.sasl.client.callback.handler.class"="software.amazon.msk.auth.iam.IAMClientCallbackHandler"
"target.cluster.consumer.security.protocol"="SASL_SSL"
"target.cluster.consumer.sasl.mechanism"="AWS_MSK_IAM"
"target.cluster.consumer.sasl.client.callback.handler.class"="software.amazon.msk.auth.iam.IAMClientCallbackHandler"
"target.cluster.consumer.sasl.jaas.config"="software.amazon.msk.auth.iam.IAMLoginModule required awsRoleArn=\"arn:aws:iam::100828196990:user/org_arun_developer1\" awsDebugCreds=true;"
"target.cluster.sasl.mechanism"="AWS_MSK_IAM"
"target.cluster.sasl.client.callback.handler.class"="software.amazon.msk.auth.iam.IAMClientCallbackHandler"
"refresh.groups.enabled"="true"
"refresh.groups.interval.seconds"="60"
"refresh.topics.interval.seconds"="60"
"topics.exclude"=".*[-.]internal,.*.replica,__.*,.*-config,.*-status,.*-offset"
"emit.checkpoints.enabled"="true"
"topics"=".*"
"value.converter"="org.apache.kafka.connect.converters.ByteArrayConverter"
"key.converter"="org.apache.kafka.connect.converters.ByteArrayConverter"
"sync.topic.configs.enabled"="true"
"sync.topic.configs.interval.seconds"="60"
"refresh.topics.enabled"="true"
"groups.exclude"="console-consumer-.*,connect-.*,__.*"
"consumer.auto.offset.reset"="earliest"
"replication.factor"="3"
}

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = "b-1.secondarykafkacluster.wjy7cv.c10.kafka.us-west-2.amazonaws.com:9094,b-2.secondarykafkacluster.wjy7cv.c10.kafka.us-west-2.amazonaws.com:9094,b-3.secondarykafkacluster.wjy7cv.c10.kafka.us-west-2.amazonaws.com:9094"

      vpc {
        security_groups = [aws_security_group.sg.id]
        subnets         = [aws_subnet.subnet_az1.id,
        aws_subnet.subnet_az2.id,
        aws_subnet.subnet_az3.id,
        ]
      }
    }
  }

  kafka_cluster_client_authentication {
    authentication_type = "NONE"
  }

  kafka_cluster_encryption_in_transit {
    encryption_type = "TLS"
  }

  plugin {
    custom_plugin {
      arn      = aws_mskconnect_custom_plugin.example.arn
      revision = aws_mskconnect_custom_plugin.example.latest_revision
    }
  }

  service_execution_role_arn = "arn:aws:iam::100828196990:user/org_arun_developer1"
}