locals {
  application_id = "arn:aws:serverlessrepo:us-east-1:625046682746:applications/serverless-iiif-cloudfront"
  host_zones     = {for host in var.aliases : host => trimprefix(host, regex("^.+?\\.", host))}
}

resource "aws_s3_bucket" "pyramid_tiff_bucket" {
  bucket = "${var.namespace}-pyramid-tiffs"
  tags   = var.tags
}

resource "aws_s3_bucket_cors_configuration" "pyramid_tiff_bucket" {
  bucket = aws_s3_bucket.pyramid_tiff_bucket.id
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

resource "aws_s3_bucket_lifecycle_configuration" "pyramid_tiff_bucket" {
  bucket = aws_s3_bucket.pyramid_tiff_bucket.id

  rule {
    id      = "intelligent-tiering"
    status  = "Enabled"

    filter {}

    transition {
      days          = 0
      storage_class = "INTELLIGENT_TIERING"
    }
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
  name   = "${var.namespace}-pyramid-bucket-access"
  policy = data.aws_iam_policy_document.pyramid_bucket_access.json
  tags   = var.tags
}

data "aws_acm_certificate" "cache_certificate" {
  domain   = var.certificate_domain
  statuses = ["ISSUED"]
}

data "external" "template_file" {
  program = ["${path.module}/scripts/prepare_template.js"]
  query = {
    applicationId = local.application_id
  }
}

resource "aws_cloudformation_stack" "serverless_iiif" {
  name          = "${var.namespace}-serverless-iiif"
  template_body = data.external.template_file.result.template
  parameters = {
    SourceBucket          = aws_s3_bucket.pyramid_tiff_bucket.id
    CacheDomainName       = join(",", var.aliases)
    CacheSSLCertificate   = data.aws_acm_certificate.cache_certificate.arn
    IiifLambdaMemory      = 2048
    PixelDensity          = 600
    ViewerRequestARN      = aws_lambda_function.iiif_trigger.qualified_arn
    ViewerRequestType     = "Lambda@Edge"
    ViewerResponseARN     = aws_lambda_function.iiif_trigger.qualified_arn
    ViewerResponseType    = "Lambda@Edge"
  }
  capabilities = ["CAPABILITY_IAM", "CAPABILITY_AUTO_EXPAND"]
  tags         = var.tags
}

data "aws_cloudfront_distribution" "serverless_iiif" {
  id = aws_cloudformation_stack.serverless_iiif.outputs.DistributionId
}

data "aws_route53_zone" "host_zones" {
  for_each = local.host_zones
  name     = each.value
}

resource "aws_route53_record" "serverless_iiif" {
  for_each = local.host_zones

  zone_id = data.aws_route53_zone.host_zones[each.key].zone_id
  name    = each.key
  type    = "A"

  alias {
    name                   = data.aws_cloudfront_distribution.serverless_iiif.domain_name
    zone_id                = data.aws_cloudfront_distribution.serverless_iiif.hosted_zone_id
    evaluate_target_health = true
  }
}
