variable "allow_from_referers" {
  type    = string
  default = ""
}

variable "api_token_secret" {
  type    = string
  default = null
}

variable "certificate_domain" {
  type    = string
}


variable "dc_api_endpoint" {
  type    = string
}

variable "hostname" {
  type    = string
  default = "serverless-iiif"
}
