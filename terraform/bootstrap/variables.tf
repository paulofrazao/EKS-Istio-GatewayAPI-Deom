variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-2"
}

variable "project_name" {
  description = "Project name — used to derive the state bucket name"
  type        = string
  default     = "mtkc"
}

variable "environment" {
  description = "Environment name — used to derive the state bucket name"
  type        = string
  default     = "poc"
}
