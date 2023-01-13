terraform {
  required_version = ">= 1.0"
  required_providers {
    aws         = "~> 4.0"
    external    = "~> 2.2"
    null        = "~> 3.1"
    template    = "~> 2.2"
    archive     = "~> 2.2"
  }
  backend "s3" {
    key = "iiif.tfstate"
  }
}

provider "aws" {}

locals {
  namespace      = module.core.outputs.stack.namespace

  tags = merge(
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

module "iiif_server" {
  source                = "./module"
  aliases               = var.aliases
  allow_from_referers   = var.allow_from_referers
  certificate_domain    = var.certificate_domain
  dc_api_endpoint       = var.dc_api_endpoint
  namespace             = local.namespace
  tags                  = local.tags
}