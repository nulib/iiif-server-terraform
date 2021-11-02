terraform {
  backend "s3" {
    key    = "iiif.tfstate"
  }
}

provider "aws" { }

locals {
  application_id = "arn:aws:serverlessrepo:us-east-1:625046682746:applications/serverless-iiif"
  namespace      = module.core.outputs.stack.namespace
  tags           = merge(
    module.core.outputs.stack.tags,
    {
      Component = "IIIF"
      Git       = "github.com/nulib/iiif-server-terraform"
      Project   = "Infrastructure"
    }
  )
}

module "core" {
  source    = "git::https://github.com/nulib/infrastructure.git//modules/remote_state"
  component = "core"
}

module "data_services" {
  source    = "git::https://github.com/nulib/infrastructure.git//modules/remote_state"
  component = "data_services"
}

resource "aws_s3_bucket" "pyramid_tiff_bucket" {
  bucket = "${local.namespace}-pyramid-tiffs"
  tags   = local.tags

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET"]
    allowed_origins = ["*"]
    expose_headers = [
      "x-amz-server-side-encryption",
      "x-amz-request-id",
      "x-amz-id-2"
    ]
    max_age_seconds = 3000
  }
}

data "aws_iam_policy_document" "pyramid_bucket_access" {
  statement {
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:ListAllMyBuckets"
    ]
    resources = ["arn:aws:s3:::*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:GetBucketPolicy",
      "s3:PutBucketPolicy"
    ]

    resources = [aws_s3_bucket.pyramid_tiff_bucket.arn]
  }

 statement {
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:GetObject",
      "s3:DeleteObject",
    ]

    resources = ["${aws_s3_bucket.pyramid_tiff_bucket.arn}/*"]
  }
}

resource "aws_iam_policy" "pyramid_bucket_access" {
  name   = "${local.namespace}-pyramid-bucket-access"
  policy = data.aws_iam_policy_document.pyramid_bucket_access.json
  tags   = local.tags
}

data "aws_acm_certificate" "wildcard" {
  domain   = local.secrets.certificate_domain
  statuses = ["ISSUED"]
}

data "external" "template_file" {
  program = ["${path.module}/scripts/prepare_template.js"]
  query = {
    applicationId = local.application_id
  }
}

resource "aws_cloudformation_stack" "serverless_iiif" {
  name           = "${local.namespace}-serverless-iiif"
  template_body  = data.external.template_file.result.template
  parameters = {
    SourceBucket          = aws_s3_bucket.pyramid_tiff_bucket.id
    CacheDomainName       = "${local.secrets.hostname}.${module.core.outputs.vpc.public_dns_zone.name}"
    CacheSSLCertificate   = data.aws_acm_certificate.wildcard.arn
    PixelDensity          = 600
    ViewerRequestARN      = aws_lambda_function.iiif_trigger.qualified_arn
    ViewerRequestType     = "Lambda@Edge"
    ViewerResponseARN     = aws_lambda_function.iiif_trigger.qualified_arn
    ViewerResponseType    = "Lambda@Edge"
  }
  capabilities    = ["CAPABILITY_IAM", "CAPABILITY_AUTO_EXPAND"]
  tags            = local.tags
}

data "aws_cloudfront_distribution" "serverless_iiif" {
  id = aws_cloudformation_stack.serverless_iiif.outputs.DistributionId
}

data "aws_lambda_function" "serverless_iiif" {
  function_name = aws_cloudformation_stack.serverless_iiif.outputs.LambdaFunction
}

resource "aws_iam_role_policy_attachment" "serverless_iiif_pyramid_access" {
  role          = element(split("/", data.aws_lambda_function.serverless_iiif.role), 1)
  policy_arn    = aws_iam_policy.pyramid_bucket_access.arn
}

resource "aws_route53_record" "serverless_iiif" {
  zone_id = module.core.outputs.vpc.public_dns_zone.id
  name    = "${local.secrets.hostname}.${module.core.outputs.vpc.public_dns_zone.name}"
  type    = "A"

  alias {
    name                      = data.aws_cloudfront_distribution.serverless_iiif.domain_name
    zone_id                   = data.aws_cloudfront_distribution.serverless_iiif.hosted_zone_id
    evaluate_target_health    = true
  }
}
