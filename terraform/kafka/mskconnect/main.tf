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

resource "aws_vpc_peering_connection" "vpcconnection" {
  peer_owner_id = "100828196990"
  peer_vpc_id   = data.aws_vpc.primaryvpc.id
  vpc_id        = data.aws_vpc.secondaryvpc.id
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
  depends_on = [
    aws_vpc_peering_connection.vpcconnection
  ]
}  

# Create a route table
data "aws_route_table" "rt_primary" {
  provider = aws.ireland
  vpc_id = data.aws_vpc.primaryvpc.id
  depends_on = [
    aws_vpc_peering_connection_accepter.peer
  ]
}

# Create a route
resource "aws_route" "r_primary" {
  provider = aws.ireland
  route_table_id            = data.aws_route_table.rt_primary.id
  destination_cidr_block    = "10.0.0.0/22"
  vpc_peering_connection_id = aws_vpc_peering_connection.vpcconnection.id
  depends_on = [
    data.aws_route_table.rt_primary
  ]
  }

# Create a route table
data "aws_route_table" "rt_secondary" {
  vpc_id = data.aws_vpc.secondaryvpc.id
  depends_on = [
    aws_route.r_primary
  ]
}

data "aws_msk_cluster" "secondarykafkacluster" {
  cluster_name           = "secondarykafkacluster"
}

data "aws_msk_cluster" "primarykafkacluster" {
  provider = aws.ireland
  cluster_name           = "primarykafkacluster"
}



# Create a route
resource "aws_route" "r_secondary" {
  route_table_id            = data.aws_route_table.rt_secondary.id
  destination_cidr_block    = "192.168.0.0/22"
  vpc_peering_connection_id = aws_vpc_peering_connection.vpcconnection.id
  depends_on = [
    data.aws_route_table.rt_secondary
  ]
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

resource "aws_iam_role" "role" {
  name = "MSKConnectExampleRole"

  assume_role_policy = jsonencode(
{
	"Version": "2012-10-17",
	"Statement": [
		{
			"Effect": "Allow",
			"Principal": {
				"Service": "kafkaconnect.amazonaws.com"
			},
			"Action": "sts:AssumeRole"
		},
		{
			"Effect": "Allow",
			"Principal": {
				"AWS": "arn:aws:sts::100828196990:assumed-role/MSKConnectExampleRole/100828196990"
			},
			"Action": "sts:AssumeRole"
		}
	]
}
)
}

resource "aws_iam_policy" "policy" {
  name        = "test-policy"
  description = "A test policy"

  policy = jsonencode(
  {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "kafka-cluster:*",
                "kafka:*"
            ],
            "Resource":"*"
          }
    ]
}
)
}

resource "aws_iam_role_policy_attachment" "test-attach" {
  role       = aws_iam_role.role.name
  policy_arn = aws_iam_policy.policy.arn
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
  depends_on = [
    aws_route.r_secondary
  ]
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
"tasks.max"=20
"clusters"="source,target"
"source.bootstrap.servers"="b-1.primarykafkacluster.qwkfdv.c6.kafka.eu-west-1.amazonaws.com:9092,b-3.primarykafkacluster.qwkfdv.c6.kafka.eu-west-1.amazonaws.com:9092,b-2.primarykafkacluster.qwkfdv.c6.kafka.eu-west-1.amazonaws.com:9092"
"target.bootstrap.servers"="b-1.secondarykafkacluster.evhr1x.c10.kafka.us-west-2.amazonaws.com:9092,b-3.secondarykafkacluster.evhr1x.c10.kafka.us-west-2.amazonaws.com:9092,b-2.secondarykafkacluster.evhr1x.c10.kafka.us-west-2.amazonaws.com:9092"
"emit.checkpoints.interval.seconds" = 10
"source.offset.storage.topic" = "mm2-offsets"
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

  service_execution_role_arn = "arn:aws:iam::100828196990:user/org_arun_developer1"
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
"tasks.max"=20
"clusters"="source,target"
"source.bootstrap.servers"="b-1.primarykafkacluster.qwkfdv.c6.kafka.eu-west-1.amazonaws.com:9092,b-3.primarykafkacluster.qwkfdv.c6.kafka.eu-west-1.amazonaws.com:9092,b-2.primarykafkacluster.qwkfdv.c6.kafka.eu-west-1.amazonaws.com:9092"
"target.bootstrap.servers"="b-1.secondarykafkacluster.evhr1x.c10.kafka.us-west-2.amazonaws.com:9092,b-3.secondarykafkacluster.evhr1x.c10.kafka.us-west-2.amazonaws.com:9092,b-2.secondarykafkacluster.evhr1x.c10.kafka.us-west-2.amazonaws.com:9092"
"emit.checkpoints.interval.seconds" = 10
"source.offset.storage.topic" = "mm2-offsets"
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

  service_execution_role_arn = "arn:aws:iam::100828196990:user/org_arun_developer1"
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
"tasks.max"=20
"clusters"="source,target"
"source.bootstrap.servers"="b-1.primarykafkacluster.qwkfdv.c6.kafka.eu-west-1.amazonaws.com:9092,b-3.primarykafkacluster.qwkfdv.c6.kafka.eu-west-1.amazonaws.com:9092,b-2.primarykafkacluster.qwkfdv.c6.kafka.eu-west-1.amazonaws.com:9092"
"target.bootstrap.servers"="b-1.secondarykafkacluster.evhr1x.c10.kafka.us-west-2.amazonaws.com:9092,b-3.secondarykafkacluster.evhr1x.c10.kafka.us-west-2.amazonaws.com:9092,b-2.secondarykafkacluster.evhr1x.c10.kafka.us-west-2.amazonaws.com:9092"
"emit.checkpoints.interval.seconds" = 10
"source.offset.storage.topic" = "mm2-offsets"
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

  service_execution_role_arn = "arn:aws:iam::100828196990:user/org_arun_developer1"
}

