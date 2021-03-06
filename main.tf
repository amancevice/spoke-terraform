# Spoke on AWS
# 
# This will automate creation of resources for running Spoke on AWS. This only
# takes care of the resource creation listed in the first section of the AWS
# Deploy guide (docs/DEPLOYING_AWS_LAMBDA.md). It will _not_ actually deploy
# the code.
# 
# Author: @bchrobot <benjamin.blair.chrobot@gmail.com>
# Version 0.1.0



# Configure AWS Provider
# Source: https://www.terraform.io/docs/providers/aws/index.html
provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "${var.aws_region}"
}



# Lookup the certificate (must be created _before_ running `terraform apply`)
# Source: https://www.terraform.io/docs/providers/aws/d/acm_certificate.html
# data "aws_acm_certificate" "spoke_certificate" {
#   domain   = "${var.spoke_domain}"
#   statuses = ["ISSUED"]
# }
# Could also create cert (and then wait for validation):
# Source: https://www.terraform.io/docs/providers/aws/r/acm_certificate.html
resource "aws_acm_certificate" "spoke_cert" {
  domain_name       = "${var.spoke_domain}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}



# Create the bucket
# Source: https://www.terraform.io/docs/providers/aws/r/s3_bucket.html
resource "aws_s3_bucket" "spoke_bucket" {
  bucket = "${var.s3_bucket_name}"
  acl    = "private"

  tags {
    Name = "Spoke Bucket"
  }
}



# Create VPC
# Source: https://www.terraform.io/docs/providers/aws/r/vpc.html
resource "aws_vpc" "spoke_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support     = true
  enable_dns_hostnames   = true

  tags {
    Name = "Spoke VPC"
  }
}



# Create Internet Gateway
# Source: https://www.terraform.io/docs/providers/aws/r/internet_gateway.html
resource "aws_internet_gateway" "gw" {
  vpc_id = "${aws_vpc.spoke_vpc.id}"

  tags {
    Name = "Spoke IGW"
  }
}



# Create Subnets
# Source: https://www.terraform.io/docs/providers/aws/r/subnet.html

# Public A
resource "aws_subnet" "public_a" {
  vpc_id     = "${aws_vpc.spoke_vpc.id}"
  cidr_block = "10.0.1.0/24"
  availability_zone = "${var.aws_region}a"

  tags {
    Name = "Public A"
  }
}

# Public B
resource "aws_subnet" "public_b" {
  vpc_id     = "${aws_vpc.spoke_vpc.id}"
  cidr_block = "10.0.2.0/24"
  availability_zone = "${var.aws_region}b"

  tags {
    Name = "Public B"
  }
}

# Private A
resource "aws_subnet" "private_a" {
  vpc_id     = "${aws_vpc.spoke_vpc.id}"
  cidr_block = "10.0.3.0/24"
  availability_zone = "${var.aws_region}a"

  tags {
    Name = "Private A"
  }
}

# Private B
resource "aws_subnet" "private_b" {
  vpc_id     = "${aws_vpc.spoke_vpc.id}"
  cidr_block = "10.0.4.0/24"
  availability_zone = "${var.aws_region}b"

  tags {
    Name = "Private B"
  }
}



# Create EIP for NAT
# Source: https://www.terraform.io/docs/providers/aws/r/eip.html
resource "aws_eip" "lambda_nat" {
  vpc = true

  depends_on                = ["aws_internet_gateway.gw"]
}



# Create NAT Gateway
# Source: https://www.terraform.io/docs/providers/aws/r/nat_gateway.html
resource "aws_nat_gateway" "gw" {
  allocation_id = "${aws_eip.lambda_nat.id}"
  subnet_id     = "${aws_subnet.public_a.id}"

  tags {
    Name = "Lambda NAT"
  }

  # Source: https://www.terraform.io/docs/providers/aws/r/nat_gateway.html#argument-reference
  depends_on = ["aws_internet_gateway.gw"]
}



# Create Route Tables
# Source: https://www.terraform.io/docs/providers/aws/r/route_table.html

# Public
resource "aws_route_table" "public" {
  vpc_id = "${aws_vpc.spoke_vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.gw.id}"
  }

  tags {
    Name = "Public Route Table"
  }
}

# Private
resource "aws_route_table" "private" {
  vpc_id = "${aws_vpc.spoke_vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = "${aws_nat_gateway.gw.id}"
  }

  tags {
    Name = "Private Route Table"
  }
}



# Add Subnets to Route Tables
# Source: https://www.terraform.io/docs/providers/aws/r/route_table_association.html

# Public Route Table
resource "aws_route_table_association" "public_a" {
  subnet_id      = "${aws_subnet.public_a.id}"
  route_table_id = "${aws_route_table.public.id}"
}
resource "aws_route_table_association" "public_b" {
  subnet_id      = "${aws_subnet.public_b.id}"
  route_table_id = "${aws_route_table.public.id}"
}

# Private Route Table
resource "aws_route_table_association" "private_a" {
  subnet_id      = "${aws_subnet.private_a.id}"
  route_table_id = "${aws_route_table.private.id}"
}
resource "aws_route_table_association" "private_b" {
  subnet_id      = "${aws_subnet.private_b.id}"
  route_table_id = "${aws_route_table.private.id}"
}



# Create Security Groups
# Source: https://www.terraform.io/docs/providers/aws/r/security_group.html

# Lambda
resource "aws_security_group" "lambda" {
  name        = "lambda"
  description = "Allow all inbound web traffic"
  vpc_id      = "${aws_vpc.spoke_vpc.id}"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    self        = true
    description = "Web traffic"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    self        = true
    description = "Encrypted web traffic"
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  tags {
    Name = "Spoke Lambda"
  }
}

# Postgres RDS
resource "aws_security_group" "postgres" {
  name        = "postgres"
  description = "Allow all inbound Postgres traffic"
  vpc_id      = "${aws_vpc.spoke_vpc.id}"

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    self        = true
    description = "Postgres access"
  }

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Postgres traffic from anywhere"
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  tags {
    Name = "Spoke Postgres"
  }
}



# Create RDS Subnet Group
# Source: https://www.terraform.io/docs/providers/aws/r/db_subnet_group.html
resource "aws_db_subnet_group" "postgres" {
  name       = "postgres"
  subnet_ids = ["${aws_subnet.public_a.id}", "${aws_subnet.public_b.id}"]

  tags {
    Name = "Spoke Postgres"
  }
}



# Create RDS Postgres instance
# Source: https://www.terraform.io/docs/providers/aws/r/db_instance.html
resource "aws_db_instance" "spoke" {
  allocated_storage      = "${var.rds_size}"
  storage_type           = "gp2"
  engine                 = "postgres"
  engine_version         = "10.4"
  instance_class         = "${var.rds_class}"
  name                   = "${var.rds_dbname}"
  port                   = "${var.rds_port}"
  username               = "${var.rds_username}"
  password               = "${var.rds_password}"
  option_group_name      = "default:postgres-10"
  parameter_group_name   = "default.postgres10"
  publicly_accessible    = true
  skip_final_snapshot    = true
  db_subnet_group_name   = "${aws_db_subnet_group.postgres.name}"
  vpc_security_group_ids = ["${aws_security_group.postgres.id}"]
}



# Create Lambda Role
# Source: https://www.terraform.io/docs/providers/aws/r/iam_role.html
resource "aws_iam_role" "spoke_lambda" {
  name = "SpokeOnLambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}



# Attach Policies to Role
# Source: https://www.terraform.io/docs/providers/aws/r/iam_role_policy_attachment.html

# AWSLambdaRole
resource "aws_iam_role_policy_attachment" "aws_lambda" {
    role       = "${aws_iam_role.spoke_lambda.name}"
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaRole"
}

# AWSLambdaVPCAccessExecutionRole
resource "aws_iam_role_policy_attachment" "aws_lambda_vpc_access_execution" {
    role       = "${aws_iam_role.spoke_lambda.name}"
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# AmazonS3FullAccess
resource "aws_iam_role_policy_attachment" "s3_full_access" {
    role       = "${aws_iam_role.spoke_lambda.name}"
    policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# Inline Policy
# Source: https://www.terraform.io/docs/providers/aws/r/iam_role_policy.html
resource "aws_iam_role_policy" "vpc_access_execution" {
  name = "vpc-access-execution"
  role = "${aws_iam_role.spoke_lambda.name}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "VPCAccessExecutionPermission",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "ec2:CreateNetworkInterface",
        "ec2:DeleteNetworkInterface",
        "ec2:DescribeNetworkInterfaces"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}


# Upload resources
# Source: https://www.terraform.io/docs/providers/aws/r/s3_bucket_object.html

# Upload Client Resources
resource "aws_s3_bucket_object" "client_payload" {
  acl    = "public-read"
  bucket = "${var.s3_bucket_name}"
  key    = "static/bundle.${var.client_bundle_hash}.js"
  source = "${var.client_bundle_location}"
  etag   = "${md5(file("${var.client_bundle_location}"))}"
  depends_on = ["aws_s3_bucket.spoke_bucket"]
}

# Upload Lambda Function
resource "aws_s3_bucket_object" "server_payload" {
  bucket = "${var.s3_bucket_name}"
  key    = "deploy/server.zip"
  source = "${var.server_bundle_location}"
  etag   = "${md5(file("${var.server_bundle_location}"))}"
  depends_on = ["aws_s3_bucket.spoke_bucket"]
}



# Create Lambda function
# Source: https://www.terraform.io/docs/providers/aws/r/lambda_function.html
resource "aws_lambda_function" "spoke" {
  function_name = "Spoke"
  description   = "Spoke P2P Texting Platform"

  depends_on        = ["aws_s3_bucket_object.server_payload"]
  s3_bucket         = "${var.s3_bucket_name}"
  s3_key            = "deploy/server.zip"
  source_code_hash  = "${base64sha256(file("${var.server_bundle_location}"))}"


  handler     = "lambda.handler"
  runtime     = "nodejs6.10"
  memory_size = "512"
  timeout     = "300"

  role = "${aws_iam_role.spoke_lambda.arn}"

  vpc_config = {
    subnet_ids          = ["${aws_subnet.private_a.id}", "${aws_subnet.private_b.id}"]
    security_group_ids  = ["${aws_security_group.lambda.id}"]
  }

  environment = {
    variables = {
      NODE_ENV = "production"
      JOBS_SAME_PROCESS = "1"
      SUPPRESS_SEED_CALLS = "${var.spoke_suppress_seed}"
      SUPPRESS_SELF_INVITE = "${var.spoke_suppress_self_invite}"
      AWS_ACCESS_AVAILABLE = "1"
      AWS_S3_BUCKET_NAME = "${var.s3_bucket_name}"
      APOLLO_OPTICS_KEY = ""
      DEFAULT_SERVICE = "${var.spoke_default_service}"
      OUTPUT_DIR = "./build"
      PUBLIC_DIR = "./build/client"
      ASSETS_DIR = "./build/client/assets"
      STATIC_BASE_URL = "https://s3.${var.aws_region}.amazonaws.com/${var.s3_bucket_name}/static/"
      BASE_URL = "https://${var.spoke_domain}"
      S3_STATIC_PATH = "s3://${var.s3_bucket_name}/static/"
      ASSETS_MAP_FILE = "assets.json"
      DB_HOST = "${aws_db_instance.spoke.address}"
      DB_PORT = "${aws_db_instance.spoke.port}"
      DB_NAME = "${aws_db_instance.spoke.name}"
      DB_USER = "${aws_db_instance.spoke.username}"
      DB_PASSWORD = "${var.rds_password}"
      DB_TYPE = "pg"
      DB_KEY = ""
      PGSSLMODE = "require"
      AUTH0_DOMAIN = "${var.spoke_auth0_domain}"
      AUTH0_CLIENT_ID = "${var.spoke_auth0_client_id}"
      AUTH0_CLIENT_SECRET = "${var.spoke_auth0_client_secret}"
      SESSION_SECRET = "${var.spoke_session_secret}"
      NEXMO_API_KEY = "${var.spoke_nexmo_api_key}"
      NEXMO_API_SECRET = "${var.spoke_nexmo_api_secret}"
      TWILIO_API_KEY = "${var.spoke_twilio_account_sid}"
      TWILIO_MESSAGE_SERVICE_SID = "${var.spoke_twilio_message_service_sid}"
      TWILIO_APPLICATION_SID = "${var.spoke_twilio_message_service_sid}"
      TWILIO_AUTH_TOKEN = "${var.spoke_twilio_auth_token}"
      TWILIO_STATUS_CALLBACK_URL = "https://${var.spoke_domain}/twilio-message-report"
      EMAIL_HOST = "${var.spoke_email_host}"
      EMAIL_HOST_PASSWORD = "${var.spoke_email_host_password}"
      EMAIL_HOST_USER = "${var.spoke_email_host_user}"
      EMAIL_HOST_PORT = "${var.spoke_email_host_port}"
      EMAIL_FROM = "${var.spoke_email_from}"
      ROLLBAR_CLIENT_TOKEN = "${var.spoke_rollbar_client_token}"
      ROLLBAR_ACCESS_TOKEN = "${var.spoke_rollbar_client_token}"
      ROLLBAR_ENDPOINT = "${var.spoke_rollbar_endpoint}"
      DST_REFERENCE_TIMEZONE = "${var.spoke_timezone}"
      TZ = "${var.spoke_timezone}"
      ACTION_HANDLERS = "${var.spoke_action_handlers}"
      AK_BASEURL = "${var.spoke_ak_baseurl}"
      AK_SECRET = "${var.spoke_ak_secret}"
      MAILGUN_API_KEY = "${var.spoke_mailgun_api_key}"
      MAILGUN_DOMAIN = "${var.spoke_mailgun_domain}"
      MAILGUN_PUBLIC_KEY = "${var.spoke_mailgun_public_key}"
      MAILGUN_SMTP_LOGIN = "${var.spoke_mailgun_smtp_login}"
      MAILGUN_SMTP_PASSWORD = "${var.spoke_mailgun_smtp_password}"
      MAILGUN_SMTP_PORT = "${var.spoke_mailgun_smtp_port}"
      MAILGUN_SMTP_SERVER = "${var.spoke_mailgun_smtp_server}"
      LAMBDA_DEBUG_LOG = "${var.spoke_lambda_debug}"
    }
  }
}



# Create API Gateway
# Source: https://www.terraform.io/docs/providers/aws/r/api_gateway_rest_api.html
resource "aws_api_gateway_rest_api" "spoke" {
  name        = "SpokeAPIGateway"
  description = "Spoke P2P Testing Platform"
}


# Proxy path
resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = "${aws_api_gateway_rest_api.spoke.id}"
  parent_id   = "${aws_api_gateway_rest_api.spoke.root_resource_id}"
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = "${aws_api_gateway_rest_api.spoke.id}"
  resource_id   = "${aws_api_gateway_resource.proxy.id}"
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id = "${aws_api_gateway_rest_api.spoke.id}"
  resource_id = "${aws_api_gateway_method.proxy.resource_id}"
  http_method = "${aws_api_gateway_method.proxy.http_method}"

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "${aws_lambda_function.spoke.invoke_arn}"
}


# Root path
resource "aws_api_gateway_method" "proxy_root" {
  rest_api_id   = "${aws_api_gateway_rest_api.spoke.id}"
  resource_id   = "${aws_api_gateway_rest_api.spoke.root_resource_id}"
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_root" {
  rest_api_id = "${aws_api_gateway_rest_api.spoke.id}"
  resource_id = "${aws_api_gateway_method.proxy_root.resource_id}"
  http_method = "${aws_api_gateway_method.proxy_root.http_method}"

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "${aws_lambda_function.spoke.invoke_arn}"
}


# Gateway Deployment - activate the above configuration
resource "aws_api_gateway_deployment" "spoke" {
  depends_on = [
    "aws_api_gateway_integration.lambda",
    "aws_api_gateway_integration.lambda_root",
  ]

  rest_api_id = "${aws_api_gateway_rest_api.spoke.id}"
  stage_name  = "latest"
}


# Allow API Gateway to access Lambda
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.spoke.arn}"
  principal     = "apigateway.amazonaws.com"

  # The /*/* portion grants access from any method on any resource
  # within the API Gateway "REST API".
  source_arn = "${aws_api_gateway_deployment.spoke.execution_arn}/*/*"
}
