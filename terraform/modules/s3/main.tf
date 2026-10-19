// create an S3 bucket with a name attach to it
resource "aws_s3_bucket" "primary" {
  bucket = "tharshen-terraform-primary-bucket"
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

/**
 *  the identity the OTel Collector uses to write archived log records.
 *  it is scoped by the policy below to the bucket's logs/ prefix only.
*/
resource "aws_iam_user" "log_archiver" {
  name = "tharshen-log-archiver"
}

data "aws_iam_policy_document" "log_archive" {
  statement {
    sid    = "WriteArchivedLogs"
    effect = "Allow"

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.primary.arn}/logs/*"]
  }
}

resource "aws_iam_policy" "log_archive" {
  name        = "tharshen-log-archive-write"
  description = "Least-privilege write access to the log archive bucket logs/ prefix"
  policy      = data.aws_iam_policy_document.log_archive.json
}

resource "aws_iam_user_policy_attachment" "log_archiver" {
  user       = aws_iam_user.log_archiver.name
  policy_arn = aws_iam_policy.log_archive.arn
}

output "log_archiver_user_name" {
  value       = aws_iam_user.log_archiver.name
  description = "IAM user the OTel Collector authenticates as for S3 log archive writes"
}

output "log_archive_policy_arn" {
  value       = aws_iam_policy.log_archive.arn
  description = "ARN of the least-privilege policy scoping the log archiver to the bucket logs/ prefix"
}
