// create an S3 bucket with a name attach to it
resource "aws_s3_bucket" "primary" {
  bucket = "tharshen-terraform-primary-bucket"
}

/**
 *  block every public access path to the bucket: the log archive is written and
    read only by the collector's IAM principal, never by anonymous requests
*/
resource "aws_s3_bucket_public_access_block" "primary" {
  bucket = aws_s3_bucket.primary.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

/**
 *  version the archive so an overwritten or deleted log object can be
    recovered; this bucket holds the only long-term copy of the stack's logs
*/
resource "aws_s3_bucket_versioning" "primary" {
  bucket = aws_s3_bucket.primary.id

  versioning_configuration {
    status = "Enabled"
  }
}

// encrypt archived objects at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "primary" {
  bucket = aws_s3_bucket.primary.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

/**
 *  defines the lifecycle policy after 20 days, objects from standard 
    storage class is transitioned to glacier storage class
*/
resource "aws_s3_bucket_lifecycle_configuration" "primary_lifecycle" {
  bucket = aws_s3_bucket.primary.id

  rule {
    id     = "transition-to-glacier"
    status = "Enabled"

    transition {
      days          = 20
      storage_class = "GLACIER"
    }
  }
}
