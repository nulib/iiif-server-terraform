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

variable "iiif_lambda_memory" {
  type    = number
  default = 2048
}

variable "iiif_lambda_timeout" {
  type    = number
  default = 10
}

variable "namespace" {
  type    = string
  default = ""
}

variable "sharp_layer" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "tiff_bucket_policy" {
  type    = string
  default = ""
}
