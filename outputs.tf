################################################################################
# EKS Managed Node Group
################################################################################

# output "configure_kubectl" {
#   description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
#   value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
# }

# output "emr_on_eks" {
#   description = "EMR on EKS"
#   value       = module.emr_containers
# }
################################################################################
# EMR Flink operator
################################################################################
# output "flink_job_execution_role_arn" {
#   value       = module.flink_irsa_jobs.iam_role_arn
#   description = "IAM linked role for the flink job"
# }

# output "flink_operator_role_arn" {
#   value       = module.flink_irsa_operator.iam_role_arn
#   description = "IAM linked role for the flink operator"
# }

# output "flink_operator_bucket" {
#   value       = module.s3_bucket.s3_bucket_id
#   description = "S3 bucket name for Flink operator data,logs,checkpoint and savepoint"
# }

################################################################################
# AMP
################################################################################
# output "grafana_secret_name" {
#   description = "Grafana password secret name"
#   value       = aws_secretsmanager_secret.grafana.name
# }

# output "emr_s3_bucket_name" {
#   description = "S3 bucket for EMR workloads. Scripts,Logs etc."
#   value       = module.s3_bucket.s3_bucket_id
# }
