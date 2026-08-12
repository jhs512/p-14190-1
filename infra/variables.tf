variable "prefix" {
  description = "Prefix for all resources"
  default     = "p14190"
}

variable "region" {
  description = "region"
  default     = "ap-northeast-2"
}

variable "password_1" {
  description = "공용 비밀번호 (NPMplus 관리자, PG, Redis)"
  default     = "lldj123414"
}

variable "app_1_domain" {
  description = "백엔드 도메인 (NPMplus 프록시 호스트 자동 생성용). *.vpc1-k8s.oa.gg 와일드카드가 EIP를 가리킴"
  default     = "api.vpc1-k8s.oa.gg"
}

variable "letsencrypt_email" {
  description = "Let's Encrypt 인증서 발급용 이메일"
  default     = "jangka512@gmail.com"
}

# 아래 3개는 secrets.auto.tfvars (gitignored) 로 제공하면
# 앱(스프링부트) 배포까지 테라폼이 자동으로 수행합니다. 비워두면 앱 배포는 생략.
variable "github_access_token_1_owner" {
  description = "GHCR 소유자 (read:packages 토큰 주인)"
  default     = ""
}

variable "github_access_token_1" {
  description = "GHCR read:packages 토큰"
  default     = ""
}

variable "app_1_env" {
  description = "앱 운영 시크릿 (.env 내용 통째로)"
  default     = ""
  sensitive   = true
}
