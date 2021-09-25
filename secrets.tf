locals {
  secrets = module.secrets.vars
}
module "secrets" {
  source    = "git::https://github.com/nulib/infrastructure.git//modules/secrets"
  path      = "iiif-server"
  defaults  = jsonencode({
    allow_from_referers   = ""
    certificate_domain    = "*.${module.core.outputs.vpc.public_dns_zone.name}"
    hostname              = "serverless-iiif"
  })
}
