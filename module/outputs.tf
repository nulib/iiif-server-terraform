output "endpoint" {
  value = aws_cloudformation_stack.serverless_iiif.outputs.Endpoint
}

output "pyramid_bucket" {
  value = aws_s3_bucket.pyramid_tiff_bucket.bucket
}

output "stack_name" {
  value = aws_cloudformation_stack.serverless_iiif.name
}
