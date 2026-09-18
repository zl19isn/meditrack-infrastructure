# Récupère automatiquement la dernière AMI Ubuntu 22.04 LTS officielle
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ------------------------------------------------------------------------------
# Clé SSH (Key Pair)
# ------------------------------------------------------------------------------
resource "aws_key_pair" "meditrack_key" {
  key_name   = "meditrack-key"
  public_key = file("C:/Users/Zach/.ssh/meditrack-key.pub")
}

# ------------------------------------------------------------------------------
# 1. Réseau : VPC, Subnet Public, Internet Gateway et Table de Routage
# ------------------------------------------------------------------------------
resource "aws_vpc" "meditrack_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "meditrack-vpc"
    Environment = var.environment
  }
}

resource "aws_subnet" "meditrack_public_subnet" {
  vpc_id                  = aws_vpc.meditrack_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = {
    Name        = "meditrack-public-subnet"
    Environment = var.environment
  }
}

resource "aws_internet_gateway" "meditrack_igw" {
  vpc_id = aws_vpc.meditrack_vpc.id

  tags = {
    Name        = "meditrack-igw"
    Environment = var.environment
  }
}

resource "aws_route_table" "meditrack_public_rt" {
  vpc_id = aws_vpc.meditrack_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.meditrack_igw.id
  }

  tags = {
    Name        = "meditrack-public-rt"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "meditrack_rta" {
  subnet_id      = aws_subnet.meditrack_public_subnet.id
  route_table_id = aws_route_table.meditrack_public_rt.id
}

# Groupe de sécurité (Security Group) pour l'instance EC2
resource "aws_security_group" "meditrack_ec2_sg" {
  name        = "meditrack-ec2-sg"
  description = "Autorise le flux SSH et HTTP"
  vpc_id      = aws_vpc.meditrack_vpc.id

  ingress {
    description = "Acces SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Acces HTTP pour Nginx"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "meditrack-ec2-sg"
    Environment = var.environment
  }
}

# ------------------------------------------------------------------------------
# 2. Instance EC2 Web Server (Disque EBS chiffré KMS pour HDS/RGPD)
# ------------------------------------------------------------------------------
resource "aws_instance" "meditrack_web" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.meditrack_key.key_name
  subnet_id              = aws_subnet.meditrack_public_subnet.id
  vpc_security_group_ids = [aws_security_group.meditrack_ec2_sg.id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name        = "meditrack-web-server"
    Environment = var.environment
  }
}

# ------------------------------------------------------------------------------
# 3. Bucket S3 pour le contenu statique (Bloqué au public direct)
# ------------------------------------------------------------------------------
resource "aws_s3_bucket" "meditrack_bucket" {
  bucket_prefix = "meditrack-online-assets-"

  tags = {
    Name        = "meditrack-assets-bucket"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "meditrack_s3_block" {
  bucket                  = aws_s3_bucket.meditrack_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------------------------
# 4. Distribution CloudFront + Origin Access Control (OAC) pour le HTTPS
# ------------------------------------------------------------------------------
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "meditrack-s3-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name              = aws_s3_bucket.meditrack_bucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
    origin_id                = "S3-MediTrack"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-MediTrack"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    # Redirection stricte de HTTP vers HTTPS (Conformité RGPD/HDS)
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Environment = var.environment
  }
}

# Politique S3 pour autoriser la distribution CloudFront via OAC
resource "aws_s3_bucket_policy" "allow_cloudfront" {
  bucket = aws_s3_bucket.meditrack_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipalReadOnly"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.meditrack_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.s3_distribution.arn
          }
        }
      }
    ]
  })
}