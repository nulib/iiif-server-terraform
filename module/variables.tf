variable "aliases" {
  type    = list(string)
  default = []
}

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

variable "namespace" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}