config {
  module = true
}

plugin "aws" {
  enabled = true
  version = "0.7.1"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

rule "aws_resource_missing_tags" {
  enabled   = true
  tags      = ["Component", "Environment", "Git", "Project"]
}

rule "terraform_module_pinned_source" {
  enabled             = false
  style               = "flexible"
  default_branches    = ["master"]
}