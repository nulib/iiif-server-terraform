output "endpoint" {
  value = aws_serverlessapplicationrepository_cloudformation_stack.serverless_iiif.outputs.Endpoint
}

output "stack_name" {
  value = aws_serverlessapplicationrepository_cloudformation_stack.serverless_iiif.name
}