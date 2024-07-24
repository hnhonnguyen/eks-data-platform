
#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "5.39.1"
  role_name_prefix      = format("%s-%s-", local.name, "ebs-csi-driver")
  attach_ebs_csi_policy = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
  tags = local.tags
}

#---------------------------------------------------------------
# EKS Blueprints Addons
#---------------------------------------------------------------
module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.2" # change this to version = 1.2.2 for oldder version of Karpenter deployment

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------
  # Amazon EKS Managed Add-ons
  #---------------------------------------
  eks_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
    coredns = {
      preserve = true
    }
    vpc-cni = {
      preserve = true
    }
    kube-proxy = {
      preserve = true
    }
  }

  #---------------------------------------
  # Kubernetes Add-ons
  #---------------------------------------
  #---------------------------------------------------------------
  # CoreDNS Autoscaler helps to scale for large EKS Clusters
  #   Further tuning for CoreDNS is to leverage NodeLocal DNSCache -> https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/
  #---------------------------------------------------------------
  enable_cluster_proportional_autoscaler = true
  cluster_proportional_autoscaler = {
    values = [templatefile("${path.module}/helm-values/coredns-autoscaler-values.yaml", {
      target = "deployment/coredns"
    })]
    description = "Cluster Proportional Autoscaler for CoreDNS Service"
  }

  #---------------------------------------
  # Metrics Server
  #---------------------------------------
  enable_metrics_server = true
  metrics_server = {
    values = [templatefile("${path.module}/helm-values/metrics-server-values.yaml", {})]
  }

  #---------------------------------------
  # Cluster Autoscaler
  #---------------------------------------
  enable_cluster_autoscaler = false
  cluster_autoscaler = {
    create_role = true
    values = [templatefile("${path.module}/helm-values/cluster-autoscaler-values.yaml", {
      aws_region     = var.region,
      eks_cluster_id = module.eks.cluster_name
    })]
  }

  #---------------------------------------
  # Karpenter Autoscaler for EKS Cluster
  #---------------------------------------
  enable_karpenter                  = true
  karpenter_enable_spot_termination = true
  karpenter_node = {
    iam_role_use_name_prefix = true
    iam_role_name            = "${local.name}-karpenter-node-role"
    iam_role_additional_policies = {
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
  }
  karpenter = {
    role_name           = "${local.name}-karpenter"
    chart_version       = "0.37.0"
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }

  #---------------------------------------
  # CloudWatch metrics for EKS
  #---------------------------------------
  enable_aws_cloudwatch_metrics = true
  aws_cloudwatch_metrics = {
    name      = "${local.name}-cloudwatch-metrics"
    namespace = "${local.name}-cloudwatch"
    role_name = "${local.name}-cloudwatch-metrics"
    values    = [templatefile("${path.module}/helm-values/aws-cloudwatch-metrics-values.yaml", {})]
  }

  #---------------------------------------
  # Adding AWS Load Balancer Controller
  #---------------------------------------
  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    chart_version = "1.8.1"
    name          = "${local.name}-aws-load-balancer-controller"
    role_name     = "${local.name}-alb-controller"
  }
  #---------------------------------------
  # Install cert-manager
  #---------------------------------------
  enable_cert_manager = true
  cert_manager = {
    chart_version = "1.15.1"
    depends_on    = [module.eks_blueprints_addons.aws_load_balancer_controller]
    set_values = [
      {
        name  = "extraArgs[0]"
        value = "--enable-certificate-owner-ref=false"
      },
    ]
  }
  #---------------------------------------
  # AWS for FluentBit - DaemonSet
  #---------------------------------------
  # Fluentbit is required to stream the logs to S3  when EMR Spark Operator is enabled
  enable_aws_for_fluentbit = var.enable_emr_spark_operator
  aws_for_fluentbit_cw_log_group = {
    use_name_prefix   = false
    name              = "/${local.name}/aws-fluentbit-logs" # Add-on creates this log group
    retention_in_days = 30
  }
  aws_for_fluentbit = {
    s3_bucket_arns = [
      module.s3_bucket.s3_bucket_arn,
      "${module.s3_bucket.s3_bucket_arn}/*"
    ]
    values = [templatefile("${path.module}/helm-values/aws-for-fluentbit-values.yaml", {
      region               = local.region,
      cloudwatch_log_group = "/${local.name}/aws-fluentbit-logs"
      s3_bucket_name       = module.s3_bucket.s3_bucket_id
      cluster_name         = module.eks.cluster_name
    })]
  }

  #---------------------------------------
  # Prommetheus and Grafana stack
  #---------------------------------------
  #---------------------------------------------------------------
  # Install Kafka Monitoring Stack with Prometheus and Grafana
  # 1- Grafana port-forward `kubectl port-forward svc/kube-prometheus-stack-grafana 8080:80 -n kube-prometheus-stack`
  # 2- Grafana Admin user: admin
  # 3- Get admin user password: `aws secretsmanager get-secret-value --secret-id <output.grafana_secret_name> --region $AWS_REGION --query "SecretString" --output text`
  #---------------------------------------------------------------
  # enable_kube_prometheus_stack = false
  # kube_prometheus_stack = {
  #   values = [
  #     var.enable_amazon_prometheus ? templatefile("${path.module}/helm-values/kube-prometheus-amp-enable.yaml", {
  #       region              = local.region
  #       amp_sa              = local.amp_ingest_service_account
  #       amp_irsa            = module.amp_ingest_irsa[0].iam_role_arn
  #       amp_remotewrite_url = "https://aps-workspaces.${local.region}.amazonaws.com/workspaces/${aws_prometheus_workspace.amp[0].id}/api/v1/remote_write"
  #       amp_url             = "https://aps-workspaces.${local.region}.amazonaws.com/workspaces/${aws_prometheus_workspace.amp[0].id}"
  #     }) : templatefile("${path.module}/helm-values/kube-prometheus.yaml", {})
  #   ]
  #   chart_version = "48.1.1"
  #   set_sensitive = [
  #     {
  #       name  = "grafana.adminPassword"
  #       value = data.aws_secretsmanager_secret_version.admin_password_version.secret_string
  #     }
  #   ],
  # }

  tags = local.tags
}

# resource "kubectl_manifest" "spark_monitor" {
#   yaml_body  = file("${path.module}/emr-grafana-dashboard/spark-monitor.yaml")
#   depends_on = [module.eks_blueprints_addons]
# }

#---------------------------------------------------------------
# Data on EKS Kubernetes Addons
#---------------------------------------------------------------
module "eks_data_addons" {
  source            = "aws-ia/eks-data-addons/aws"
  version           = "1.32.1" # ensure to update this to the latest/desired version
  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------------------------------
  # Kubecost Add-on
  #---------------------------------------------------------------
  # Note: Kubecost add-on depends on Kube Prometheus Stack add-on for storing the metrics
  # enable_kubecost = var.enable_kubecost
  # kubecost_helm_config = {
  #   values              = [templatefile("${path.module}/helm-values/kubecost-values.yaml", {})]
  #   version             = "1.104.5"
  #   repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  #   repository_password = data.aws_ecrpublic_authorization_token.token.password
  # }

  #---------------------------------------------------------------
  # Apache YuniKorn Add-on
  #---------------------------------------------------------------
  # enable_yunikorn = var.enable_yunikorn
  # yunikorn_helm_config = {
  #   values = [templatefile("${path.module}/helm-values/yunikorn-values.yaml", {
  #     image_version = "1.2.0"
  #   })]
  # }

  #---------------------------------------------------------------
  # EMR Spark Operator
  #---------------------------------------------------------------
  enable_emr_spark_operator = var.enable_emr_spark_operator
  emr_spark_operator_helm_config = {
    # repository          = "oci://755674844232.dkr.ecr.us-east-1.amazonaws.com"
    repository_username = data.aws_ecr_authorization_token.token.user_name
    repository_password = data.aws_ecr_authorization_token.token.password
    values = [templatefile("${path.module}/helm-values/emr-spark-operator-values.yaml", {
      aws_region = var.region
    })]
    atomic = true
  }

  #---------------------------------------------------------------
  # Spark History Server Add-on
  #---------------------------------------------------------------
  # Spark history server is required only when EMR Spark Operator is enabled
  enable_spark_history_server = var.enable_emr_spark_operator
  spark_history_server_helm_config = {
    values = [
      <<-EOT
      sparkHistoryOpts: "-Dspark.history.fs.logDirectory=s3a://${module.s3_bucket.s3_bucket_id}/${aws_s3_object.this.key}"
      EOT
    ]
  }
}

#---------------------------------------
# Karpenter Provisioners
#---------------------------------------
locals {
  provisioner_files = tolist(fileset("${path.module}/karpenter-provisioners", "data-*.yaml"))
}

resource "kubectl_manifest" "karpenter_provisioner" {
  count = length(local.provisioner_files)
  yaml_body = templatefile("${path.module}/karpenter-provisioners/${local.provisioner_files[count.index]}", {
    azs               = local.region
    eks_cluster_id    = module.eks.cluster_name
    node_iam_role_arn = split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]
  })
  depends_on = [module.eks_blueprints_addons]
}

#---------------------------------------------------------------
# Grafana Admin credentials resources
#---------------------------------------------------------------
# data "aws_secretsmanager_secret_version" "admin_password_version" {
#   secret_id  = aws_secretsmanager_secret.grafana.id
#   depends_on = [aws_secretsmanager_secret_version.grafana]
# }

# resource "random_password" "grafana" {
#   length           = 16
#   special          = true
#   override_special = "@_"
# }

# resource "random_string" "grafana" {
#   length  = 4
#   lower   = true
#   special = false
# }

# #tfsec:ignore:aws-ssm-secret-use-customer-key
# resource "aws_secretsmanager_secret" "grafana" {
#   name                    = "${local.name}-grafana-${random_string.grafana.result}"
#   recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
# }

# resource "aws_secretsmanager_secret_version" "grafana" {
#   secret_id     = aws_secretsmanager_secret.grafana.id
#   secret_string = random_password.grafana.result
# }

# Creating an s3 bucket for Spark History event logs
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket_prefix = "${local.name}-emr-"

  # For example only - please evaluate for your environment
  force_destroy = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = local.tags
}

# Creating an s3 bucket prefix. Ensure you copy Spark History event logs under this path to visualize the dags
resource "aws_s3_object" "this" {
  bucket       = module.s3_bucket.s3_bucket_id
  key          = "spark-event-logs/"
  content_type = "application/x-directory"
}
