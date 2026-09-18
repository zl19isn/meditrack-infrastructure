variable "aws_region" {
  type        = string
  default     = "eu-west-3"
  description = "Région AWS Paris"
}

variable "environment" {
  type        = string
  default     = "production"
  description = "Nom de l'environnement"
}