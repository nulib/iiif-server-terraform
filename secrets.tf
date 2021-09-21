locals {
  secrets = module.secrets.vars
}
module "secrets" {
  source    = "git::https://github.com/nulib/infrastructure.git//modules/secrets"
  path      = "iiif-server"
  defaults  = jsonencode({
    allow_from_referere   = ""
    hostname              = "serverless-iiif"
  })
}
