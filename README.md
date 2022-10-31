# aws-kafka-msk-dr-setup

\terraform\kafka\iamrole - IAM role creation required for Kafka connect - Global

\terraform\kafka\vpc
 -\primaryvpc - Creating primary vpc,  3 private subnets and 1 public subnet
 -\secondaryvpc - Creating secondary vpc,   3 private subnets and 1 public subnet
 -\vpcpeering - Create vpc peering connection between primary and secondary.

 \terraform\kafka\primary - Create primary cluster in private subnets.
 \terraform\kafka\secondary - Create secondary cluster in private subnets
 \terraform\kafka\mskconnect - Create kafka connectors for DR in secondary