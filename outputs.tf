output "endpoint" {
  value = aws_cloudformation_stack.serverless_iiif.outputs.Endpoint
}

output "stack_name" {
  value = aws_cloudformation_stack.serverless_iiif.name
}