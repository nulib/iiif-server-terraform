variable "allow_from_referers" {
  type    = string
  default = ""
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
