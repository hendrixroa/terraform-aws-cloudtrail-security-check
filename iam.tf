# Get the access to the effective Account ID in which Terraform is working.
data "aws_caller_identity" "current" {
  count = var.enabled
}

# Allow the AWS Config role to deliver logs to configured S3 Bucket.
# Derived from IAM Policy document found at https://docs.aws.amazon.com/config/latest/developerguide/s3-bucket-policy.html
data "template_file" "aws_config_policy" {
  count = var.enabled


  template = <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
        "Sid": "AWSConfigBucketPermissionsCheck",
        "Effect": "Allow",
        "Action": "s3:GetBucketAcl",
        "Resource": "$${bucket_arn}"
    },
    {
        "Sid": "AWSConfigBucketExistenceCheck",
        "Effect": "Allow",
        "Action": "s3:ListBucket",
        "Resource": "$${bucket_arn}"
    },
    {
        "Sid": "AWSConfigBucketDelivery",
        "Effect": "Allow",
        "Action": "s3:PutObject",
        "Resource": "$${resource}",
        "Condition": {
          "StringLike": {
            "s3:x-amz-acl": "bucket-owner-full-control"
          }
        }
    }
  ]
}
JSON

  vars = {
    bucket_arn = format("arn:aws:s3:::%s", var.config_logs_bucket)
    resource   = format("arn:aws:s3:::%s/%s/AWSLogs/%s/Config/*", var.config_logs_bucket, var.config_logs_prefix, data.aws_caller_identity.current[count.index].account_id)
  }
}

# Allow IAM policy to assume the role for AWS Config
data "aws_iam_policy_document" "aws-config-role-policy" {
  count = var.enabled

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    effect = "Allow"
  }
}

#
# IAM
#

resource "aws_iam_role" "main" {
  count = var.enabled

  name               = "aws-config-role"
  assume_role_policy = data.aws_iam_policy_document.aws-config-role-policy[count.index].json
}

resource "aws_iam_policy_attachment" "managed-policy" {
  count = var.enabled

  name       = "aws-config-managed-policy"
  roles      = [aws_iam_role.main[count.index].name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSConfigRole"
}

resource "aws_iam_policy" "aws-config-policy" {
  count = var.enabled

  name   = "aws-config-policy"
  policy = data.template_file.aws_config_policy[count.index].rendered
}

resource "aws_iam_policy_attachment" "aws-config-policy" {
  count = var.enabled

  name       = "aws-config-policy"
  roles      = [aws_iam_role.main[count.index].name]
  policy_arn = aws_iam_policy.aws-config-policy[count.index].arn
}
