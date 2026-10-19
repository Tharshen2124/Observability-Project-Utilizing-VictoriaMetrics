terraform {
    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = "6.43.0"
        }
    }
}
provider "aws" {
    # Config options
    region = "us-east-1"
}

module "s3_bucket" {
  source = "./modules/s3"
}

output "log_archiver_user_name" {
  value       = module.s3_bucket.log_archiver_user_name
  description = "IAM user the OTel Collector authenticates as for S3 log archive writes"
}
