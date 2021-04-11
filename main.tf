terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_route53_zone" "primary" {
  name = "ashleyconnor.co.uk"
}

resource "aws_route53_record" "apex" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "ashleyconnor.co.uk"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cloudfront-dist["ashleyconnor"].domain_name
    zone_id                = aws_cloudfront_distribution.cloudfront-dist["ashleyconnor"].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "til" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "til.ashleyconnor.co.uk"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.cloudfront-dist["til-ashleyconnor"].domain_name
    zone_id                = aws_cloudfront_distribution.cloudfront-dist["til-ashleyconnor"].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_s3_bucket" "ashleyconnor" {
  bucket = "ashleyconnor.co.uk"

  website {
    index_document = "index.html"
    error_document = "error.html"
  }

  logging {
    target_bucket = "logs.ashleyconnor.co.uk"
    target_prefix = "root/"
  }

  cors_rule {
    allowed_headers = ["Authorization"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = []
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_policy" "ashleyconnor-policy" {
  bucket = aws_s3_bucket.ashleyconnor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "ashleyconnor-bucket-policy"
    Statement = [
      {
        Sid    = "AddPerm"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = "s3:GetObject"
        Resource = [
          "${aws_s3_bucket.ashleyconnor.arn}/*",
        ]
      },
    ]
  })
}

resource "aws_s3_bucket" "www-ashleyconnor" {
  bucket = "www.ashleyconnor.co.uk"

  website {
    redirect_all_requests_to = "ashleyconnor.co.uk"
  }
}

data "aws_acm_certificate" "ashleyconnor-wildcard-cert" {
  domain   = "*.ashleyconnor.co.uk"
  statuses = ["ISSUED"]
}

locals {
  s3_origin_id = "Custom-${aws_s3_bucket.ashleyconnor.website_endpoint}"
}

resource "aws_cloudfront_distribution" "cloudfront-dist" {
  for_each = {
    ashleyconnor = {
      aliases = ["ashleyconnor.co.uk"]
      origin_path = null
      logging_prefix = "cdn/"
    },
    til-ashleyconnor = {
      aliases = ["til.ashleyconnor.co.uk"]
      origin_path = "/til"
      logging_prefix = "cdn/til/"
    }
  }
  enabled = true
  default_root_object = "index.html"
  aliases = each.value.aliases

  viewer_certificate {
    acm_certificate_arn = data.aws_acm_certificate.ashleyconnor-wildcard-cert.arn
    ssl_support_method  = "sni-only"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    compress         = true
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
  }

  logging_config {
    bucket          = "logs.ashleyconnor.co.uk.s3.amazonaws.com"
    include_cookies = false
    prefix          = each.value.logging_prefix
  }

  origin {
    domain_name = aws_s3_bucket.ashleyconnor.website_endpoint
    origin_id   = local.s3_origin_id
    origin_path = each.value.origin_path

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "http-only"
      origin_read_timeout      = 30
      origin_ssl_protocols = [
        "SSLv3",
        "TLSv1",
      ]
    }
  }
}
