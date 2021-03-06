
data "aws_iam_policy_document" "assume" {
  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRole"
    ]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "rotation" {
  statement {
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DetachNetworkInterface",
    ]
    resources = ["*", ]
  }
  statement {
    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecretVersionStage",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:*",
    ]
  }
  statement {
    actions   = ["secretsmanager:GetRandomPassword"]
    resources = ["*", ]
  }
}

// Lambda Policies

resource "aws_iam_policy_attachment" "basic_execution" {
  count      = var.enabled ? 1 : 0
  name       = "lambda-rds-rotation-execution-policy"
  roles      = [aws_iam_role.lambda.0.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy_attachment" "vpc_execution" {
  count      = var.enabled ? 1 : 0
  name       = "lambda-rds-rotation-execution-policy"
  roles      = [aws_iam_role.lambda.0.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_policy" "rotation" {
  count  = var.enabled ? 1 : 0
  name   = "lambda-rds-rotation-policy"
  path   = "/"
  policy = data.aws_iam_policy_document.rotation.json
}

resource "aws_iam_policy_attachment" "rotation" {
  count      = var.enabled ? 1 : 0
  name       = "lambda-rds-rotation-policy-attachment"
  roles      = [aws_iam_role.lambda.0.name]
  policy_arn = aws_iam_policy.rotation.0.arn
}

// Lambda Role
resource "aws_iam_role" "lambda" {
  count              = var.enabled ? 1 : 0
  name               = "lambda-rds-rotation-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = module.role_label.tags
}

// Lambda Function
resource "aws_lambda_function" "lambda" {
  count            = var.enabled ? 1 : 0
  function_name    = "lambda-rds-rotation-function"
  filename         = var.filename
  source_code_hash = filebase64sha256(var.filename)
  role             = aws_iam_role.lambda.0.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.7"
  tags             = module.lambda_label.tags

  vpc_config {
    security_group_ids = var.security_group_ids
    subnet_ids         = var.subnet_ids
  }

  timeout     = 30
  description = "Managed by Terraform, Conducts an AWS SecretsManager secret rotation for RDS MySQL using single user rotation scheme"
  environment {
    variables = { #https://docs.aws.amazon.com/general/latest/gr/rande.html#asm_region
      SECRETS_MANAGER_ENDPOINT = var.secretsmanager_vpc_endpoint == "" ? "https://secretsmanager.${data.aws_region.current.name}.amazonaws.com" : var.secretsmanager_vpc_endpoint
    }
  }
}

# resource "aws_cloudwatch_log_group" "default" {
#   count             = var.enabled ? 1 : 0
#   name              = "/aws/lambda/${aws_lambda_function.lambda.0.id}"
#   retention_in_days = var.automatically_after_days
#   kms_key_id        = aws_kms_key.default.0.id
#   tags              = module.lambda_label.tags
# }

// Lambda Permission
resource "aws_lambda_permission" "lambda" {
  count         = var.enabled ? 1 : 0
  function_name = aws_lambda_function.lambda.0.function_name
  statement_id  = "AllowExecutionSecretManager"
  action        = "lambda:InvokeFunction"
  principal     = "secretsmanager.amazonaws.com"
}
