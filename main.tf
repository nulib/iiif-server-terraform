terraform {
  backend "s3" {
    key    = "iiif.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  namespace     = module.core.outputs.stack.namespace
  tags          = merge(module.core.outputs.stack.tags, {Component = "IIIF"})
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
  domain   = "*.${module.core.outputs.vpc.public_dns_zone.name}"
  statuses = ["ISSUED"]
}

resource "aws_serverlessapplicationrepository_cloudformation_stack" "serverless_iiif" {
  name           = "${local.namespace}-serverless-iiif"
  application_id = "arn:aws:serverlessrepo:us-east-1:625046682746:applications/serverless-iiif"
  parameters = {
    SourceBucket          = aws_s3_bucket.pyramid_tiff_bucket.id
    CacheDomainName       = "${var.hostname}.${module.core.outputs.vpc.public_dns_zone.name}"
    CacheSSLCertificate   = data.aws_acm_certificate.wildcard.arn
    PreflightFunctionARN  = aws_lambda_function.iiif_preflight.qualified_arn
    PreflightFunctionType = "Lambda@Edge"
  }
  capabilities    = ["CAPABILITY_IAM", "CAPABILITY_RESOURCE_POLICY"]
  tags            = local.tags
}

data "aws_cloudfront_distribution" "serverless_iiif" {
  id = aws_serverlessapplicationrepository_cloudformation_stack.serverless_iiif.outputs.DistributionId
}

resource "aws_route53_record" "serverless_iiif" {
  zone_id = module.core.outputs.vpc.public_dns_zone.id
  name    = "${var.hostname}.${module.core.outputs.vpc.public_dns_zone.name}"
  type    = "A"

  alias {
    name                      = data.aws_cloudfront_distribution.serverless_iiif.domain_name
    zone_id                   = data.aws_cloudfront_distribution.serverless_iiif.hosted_zone_id
    evaluate_target_health    = true
  }
}
