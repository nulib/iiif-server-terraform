resource "aws_cloudwatch_log_group" "trigger_lambda_logs" {
  name = "/aws/lambda/${local.namespace}-serverless-iiif-trigger"
  tags = local.tags
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = [
        "edgelambda.amazonaws.com",
        "lambda.amazonaws.com"
      ]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy" "basic_lambda_execution" {
  name = "AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role" "lambda_role" {
  name               = "${local.namespace}-serverless-iiif"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "lambda_bucket_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.pyramid_bucket_access.arn
}

resource "aws_iam_role_policy_attachment" "lambda_elasticsearch_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = module.data_services.outputs.elasticsearch.read_policy_arn
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution_role" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = data.aws_iam_policy.basic_lambda_execution.arn
}

locals {
  source_sha = sha1(join("", [for f in fileset(path.module, "src/*"): sha1(file(f))]))
}

resource "null_resource" "node_modules" {
  triggers = {
    source = local.source_sha
  }

  provisioner "local-exec" {
    command     = "npm install --no-bin-links"
    working_dir = template_dir.function_source.destination_dir
  }
}

resource "template_dir" "function_source" {
  source_dir      = "${path.module}/src"
  destination_dir = "${path.module}/build"

  vars = {
    allow_from       = var.allow_from_referers
    api_token_secret = var.api_token_secret
    auth_domain      = module.core.outputs.vpc.public_dns_zone.name
    elastic_search   = module.data_services.outputs.elasticsearch.endpoint
    tiff_bucket      = aws_s3_bucket.pyramid_tiff_bucket.id
  }
}

data "archive_file" "trigger_lambda" {
  depends_on    = [null_resource.node_modules]
  type          = "zip"
  source_dir    = template_dir.function_source.destination_dir
  output_path   = "${path.module}/package/${local.source_sha}.zip"
}

resource "aws_lambda_function" "iiif_trigger" {
  filename      = data.archive_file.trigger_lambda.output_path
  function_name = "${local.namespace}-serverless-iiif-trigger"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs14.x"
  memory_size   = 128
  timeout       = 5
  publish       = true
  tags          = local.tags
}

resource "aws_lambda_permission" "allow_edge_invocation" {
  action          = "lambda:InvokeFunction"
  function_name   = aws_lambda_function.iiif_trigger.arn
  qualifier       = aws_lambda_function.iiif_trigger.version
  principal       = "cloudfront.amazonaws.com"
  source_arn      = data.aws_cloudfront_distribution.serverless_iiif.arn

  lifecycle {
    create_before_destroy = true
  }
}