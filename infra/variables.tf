variable "region" {
  description = "region"
  default     = "ap-northeast-2"
}

variable "prefix" {
  description = "Prefix for all resources"
  default     = "terra"
}

variable "app_1_domain" {
  description = "app_1 domain"
  default     = "api.vpc1-k8s.oa.gg"
}