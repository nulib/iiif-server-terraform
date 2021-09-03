variable "allow_from_referers" {
  type    = string
  default = ""
}

variable "api_token_secret" {
  type    = string
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "hostname" {
  type    = string
  default = "serverless-iiif"
}
