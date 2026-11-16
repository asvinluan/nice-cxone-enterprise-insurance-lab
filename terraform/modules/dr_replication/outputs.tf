output "dr_bucket_id" {
  description = "DR archive bucket name."
  value       = aws_s3_bucket.dr.id
}
