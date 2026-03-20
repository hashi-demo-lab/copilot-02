data "aws_iam_policy_document" "content_bucket_policy" {
  statement {
    sid = "AllowCloudFrontOriginAccessIdentityReadOnly"

    actions = [
      "s3:GetObject",
    ]

    resources = [
      local.content_bucket_object_arn,
    ]

    principals {
      type        = "AWS"
      identifiers = local.content_bucket_policy_principal_arns
    }
  }
}
