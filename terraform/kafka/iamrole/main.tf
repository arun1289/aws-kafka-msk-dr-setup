
resource "aws_iam_role" "MSKConnectMirrorRole" {
  name = "MSKConnectMirror"

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
		}
#      this doesn't work or I don't understand what it should be changed to. 100828196990 is account number
#      what exactly this policy is doing?
#        ,{
#			"Effect": "Allow",
#			"Principal": {
#				"AWS": "arn:aws:sts::100828196990:assumed-role/MSKConnectMirror/100828196990"
#			},
#			"Action": "sts:AssumeRole"
#		}
	]
}
)
}

resource "aws_iam_policy" "KafkaAdminFullAccess" {
  name        = "KafkaAdminFullAccess"
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

resource "aws_iam_role_policy_attachment" "MSKConnectMirrorRolePolicyAttachment" {
  role       = aws_iam_role.MSKConnectMirrorRole.name
  policy_arn = aws_iam_policy.KafkaAdminFullAccess.arn
}

