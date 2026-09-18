output "ec2_public_ip" {
  value       = aws_instance.meditrack_web.public_ip
  description = "Adresse IP publique du serveur EC2 MediTrack"
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.s3_distribution.domain_name
  description = "URL publique sécurisée CloudFront (HTTPS)"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.meditrack_bucket.id
  description = "Nom du bucket S3 généré"
}