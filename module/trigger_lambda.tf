resource "aws_cloudwatch_log_group" "trigger_lambda_logs" {
  name = "/aws/lambda/${var.namespace}-serverless-iiif-trigger"
  tags = var.tags
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
  name               = "${var.namespace}-serverless-iiif"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "lambda_bucket_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.pyramid_bucket_access.arn
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution_role" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = data.aws_iam_policy.basic_lambda_execution.arn
}

locals {
  source_sha = sha1(join("", [for f in fileset("", "${path.module}/src/*"): sha1(file(f))]))
  variable_sha = sha1(join("", [for v in [var.dc_api_endpoint, var.allow_from_referers, aws_s3_bucket.pyramid_tiff_bucket.id]: sha1(v)]))
}

resource "null_resource" "node_modules" {
  depends_on = [
    local_file.function_source
  ]

  triggers = {
    node_modules    = fileexists("module/build/node_modules/.package-lock.json")
    source          = local.source_sha
    vars            = local.variable_sha
  }

  provisioner "local-exec" {
    command     = "npm install --no-bin-links"
    working_dir = "${path.module}/build"
  }
}

resource "local_file" "function_source" {
  for_each = toset([for f in fileset("", "${path.module}/src/*"): basename(f)])
  filename = "${path.module}/build/${each.key}"
  content = templatefile(
    "${path.module}/src/${each.key}",
    {
      allow_from       = var.allow_from_referers
      dc_api_endpoint  = var.dc_api_endpoint
      tiff_bucket      = aws_s3_bucket.pyramid_tiff_bucket.id
    }
  )
}

data "archive_file" "trigger_lambda" {
  depends_on    = [null_resource.node_modules]
  type          = "zip"
  source_dir    = "${path.module}/build"
  output_path   = "${path.module}/package/${local.source_sha}${local.variable_sha}.zip"
}

resource "aws_lambda_function" "iiif_trigger" {
  filename            = data.archive_file.trigger_lambda.output_path
  function_name       = "${var.namespace}-serverless-iiif-trigger"
  role                = aws_iam_role.lambda_role.arn
  handler             = "index.handler"
  runtime             = "nodejs16.x"
  memory_size         = 128
  timeout             = 5
  publish             = true
  source_code_hash    = data.archive_file.trigger_lambda.output_sha
  tags                = var.tags
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