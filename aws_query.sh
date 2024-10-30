#!/usr/bin/env bash

# set default CLI region with aws configure
# set AWS_DEFAULT_REGION to scan a non-default region

# Get AWS account and region context
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
REGION=$(aws sts get-caller-identity --query 'Arn' --output text | cut -d: -f4)
echo "starting scan using AWS Account: ${ACCOUNT_ID} Region: ${REGION}"

# Get list of AWS Accounts
echo "list accounts..."
aws organizations list-accounts --query 'Accounts[*].[Id,Name]' --output text > aws_accounts.txt

# ELBs
echo "list elastic load balancers..."
aws elb describe-load-balancers --query 'LoadBalancerDescriptions[*].{ARN: join("", ["arn:aws:elasticloadbalancing:", `Region`, ":", `AccountId`, ":loadbalancer/", LoadBalancerName])}' --output json | jq -r '.[].ARN' > elb_arns.txt
aws elbv2 describe-load-balancers --query 'LoadBalancers[*].LoadBalancerArn' --output json | jq -r '.[]' >>elb_arns.txt

# WAFs
echo "list web application firewalls..."
aws wafv2 list-web-acls --scope REGIONAL --query 'WebACLs[*].ARN' --output json | jq -r '.[]' >waf_arns.txt
aws wafv2 list-web-acls --scope CLOUDFRONT --query 'WebACLs[*].ARN' --output json | jq -r '.[]' >>waf_arns.txt

# ElastiCache
echo "list elastic caches..."
aws elasticache describe-cache-clusters --query 'CacheClusters[*].{ARN: join("", ["arn:aws:elasticache:", `Region`, ":", `AccountId`, ":cluster:", CacheClusterId])}' --output json | jq -r '.[].ARN' >elasticache_arns.txt

# EC2 Instances
echo "list EC2 instances..."
aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId, Placement.AvailabilityZone]' --output text | \
awk '{print "arn:aws:ec2:"$2":"$ACCOUNT_ID:instance:"$1}' > ec2_instances_arns.txt

# S3 Buckets
echo "list S3 buckets..."
aws s3api list-buckets --query 'Buckets[*].Name' --output text | \
awk '{print "arn:aws:s3:::"$1}' > s3_buckets_arns.txt

# RDS Instances
echo "list RDS instances..."
aws rds describe-db-instances --query 'DBInstances[*].[DBInstanceIdentifier, DBInstanceArn]' --output text > rds_instances_arns.txt

# Lambda Functions
echo "list Lambda functions..."
aws lambda list-functions --query 'Functions[*].FunctionArn' --output text > lambda_functions_arns.txt

# DynamoDB Tables
echo "list DynamoDB tables..."
aws dynamodb list-tables --query 'TableNames' --output text | \
awk '{print "arn:aws:dynamodb:$REGION:"$ACCOUNT_ID:table:"$1}' > dynamodb_tables_arns.txt

# CloudFormation Stacks
echo "list CloudFormation stacks..."
aws cloudformation list-stacks --query 'StackSummaries[*].[StackName, StackId]' --output text > cloudformation_stacks_arns.txt

# ECS Clusters
echo "list ECS clusters..."
aws ecs list-clusters --query 'clusterArns[*]' --output text > ecs_clusters_arns.txt

# EKS Clusters
echo "list EKS clusters..."
aws eks list-clusters --query 'clusters[*]' --output text | \
awk '{print "arn:aws:eks:$REGION:$ACCOUNT_ID:cluster/"$1}' > eks_clusters_arns.txt

# ECR repositories
echo "list ECR repositories..."
aws ecr describe-repositories --query 'repositories[*].repositoryArn' --output text > ecr_repos_arns.txt

# Redshift Clusters
echo "list redshift clusters..."
aws redshift describe-clusters --query 'Clusters[*].[ClusterIdentifier, ClusterArn]' --output text > redshift_clusters_arns.txt

# SNS Topics
echo "list SNS topics..."
aws sns list-topics --query 'Topics[*].TopicArn' --output text > sns_topics_arns.txt

# SQS Queues
echo "list SQS queues..."
aws sqs list-queues --query 'QueueUrls' --output text | \
awk -F'/' '{print "arn:aws:sqs:"$2":$ACCOUNT_ID:"$4}' > sqs_queues_arns.txt

# Elastic Beanstalk Applications
echo "list EBS apps..."
aws elasticbeanstalk describe-applications --query 'Applications[*].ApplicationName' --output text | \
awk '{print "arn:aws:elasticbeanstalk:$REGION:$ACCOUNT_ID:application/"$1}' > eb_applications_arns.txt

# API Gateway APIs
echo "list API gateways..."
aws apigateway get-rest-apis --query 'items[*].id' --output text | \
awk '{print "arn:aws:apigateway:$REGION::/restapis/"$1}' > api_gateway_arns.txt

# List Tagged Resources
echo "list tagged resources..."
aws resourcegroupstaggingapi get-resources --query 'ResourceTagMappingList[*].ResourceARN' --output text > tagged_resources.txt

# List Resource Groups
echo "list resource groups..."
aws resource-groups list-groups --query 'GroupIdentifiers[*].GroupName' --output text > resource_groups.txt

# Get Grouped Resources
echo "find grouped resources..."
for group in $(cat resource_groups.txt); do
  aws resource-groups get-group-resources --group-name "$group" --query 'ResourceIdentifiers[*].ResourceARN' --output text >> grouped_resources.txt
done

# Find Untagged and Ungrouped Resources
echo "find untagged and ungrouped resources..."
cat *_arn.txt > all_resources.txt
sort all_resources.txt -o all_resources.txt
sort tagged_resources.txt -o tagged_resources.txt
sort grouped_resources.txt -o grouped_resources.txt
comm -13 tagged_resources.txt grouped_resources.txt > untagged_and_ungrouped_resources.txt

# Establish start and end dates for billing queries
START=$(date -d "-1 month" +"%Y-%m-01")
END=$(date +"%Y-%m-01")

# Get billing information by account
echo "get-cost-and-usage for all accounts..."
aws ce get-cost-and-usage \
  --time-period Start=$START,End=$END \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --group-by Type=DIMENSION,Key=LINKED_ACCOUNT \
  --query 'ResultsByTime[0].Groups[*].[Keys[0],Metrics.AmortizedCost.Amount]' \
  --output text > billing_report_accounts.txt
# Convert to CSV Format
echo "account, cost" > billing_report_accounts.csv
cat billing_report_accounts.txt | tr -s '\t' ',' >> billing_report_accounts.csv

# Get tag keys
echo "get-tag-keys..."
aws resourcegroupstaggingapi get-tag-keys --query 'TagKeys' --output text > tag_keys.txt

# Get billing information for each tag key
for TAG_KEY in $(cat tag_keys.txt); do
  echo "get-cost-and-usage for tag $TAG_KEY..."
  aws ce get-cost-and-usage \
    --time-period Start=$START,End=$END \
    --granularity MONTHLY \
    --metrics "UnblendedCost" \
    --group-by Type=TAG,Key=$TAG_KEY \
    --query 'ResultsByTime[0].Groups[*].[Keys[0],Metrics.AmortizedCost.Amount]' \
    --output text > billing_report_$TAG_KEY.txt
  echo "region, cost" > billing_report_$TAG_KEY.csv
  cat billing_report_$TAG_KEY.txt | tr -s '\t' ',' >> billing_report_$TAG_KEY.csv
done
