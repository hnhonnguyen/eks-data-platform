provider "aws" {
  region = local.region
}

# ECR always authenticates with `us-east-1` region
# Docs -> https://docs.aws.amazon.com/AmazonECR/latest/public/public-registries.html
provider "aws" {
  alias  = "ecr"
  region = "us-east-1"
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  # token                  = data.aws_eks_cluster_auth.this.token
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--region", local.region, "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubectl" {
  apply_retry_count      = 30
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false
  token                  = data.aws_eks_cluster_auth.this.token
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

# data "aws_ecrpublic_authorization_token" "token" {
#   provider = aws.ecr
# }

# This ECR "registry_id" number refers to the AWS account ID for us-west-2 region
# if you are using a different region, make sure to change it, you can get the account from the link below
# https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/docker-custom-images-tag.html
# data "aws_ecr_authorization_token" "token" {
#   registry_id = var.registry_id
# }

# data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  name   = var.name
  region = var.region

  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  tags = merge(var.tags, {
    Blueprint = local.name
  })
}

#---------------------------------------------------------------
# EKS Cluster
#---------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.18"

  cluster_name    = local.name
  cluster_version = var.eks_cluster_version

  # if true, Your cluster API server is accessible from the internet. You can, optionally, limit the CIDR blocks that can access the public endpoint.
  #WARNING: Avoid using this option (cluster_endpoint_public_access = true) in preprod or prod accounts. This feature is designed for sandbox accounts, simplifying cluster deployment and testing.
  cluster_endpoint_public_access = false

  vpc_id = data.aws_vpc.vendor1.id
  # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the EKS Control Plane ENIs will be created
  subnet_ids = [for subnet in data.aws_subnet.eks_subnet : subnet.id]
  # create_aws_auth_configmap = true
  manage_aws_auth_configmap = true
  aws_auth_roles = [
    # We need to add in the Karpenter node IAM role for nodes launched by Karpenter
    {
      rolearn  = module.eks_blueprints_addons.karpenter.node_iam_role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups = [
        "system:bootstrappers",
        "system:nodes",
      ]
    },
    {
      # Required for EMR on EKS virtual cluster
      rolearn  = "arn:aws:iam::${var.account_id}:role/AWSServiceRoleForAmazonEMRContainers"
      username = "emr-containers"
      groups   = []
    },
  ]

  #---------------------------------------
  # Note: This can further restricted to specific required for each Add-on and your application
  #---------------------------------------
  # Extend cluster security group rules
  cluster_security_group_additional_rules = {
    ingress_nodes_ephemeral_ports_tcp = {
      description                = "Nodes on ephemeral ports"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "ingress"
      source_node_security_group = true
    }
  }

  # Extend node-to-node security group rules
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
  }

  eks_managed_node_group_defaults = {
    iam_role_additional_policies = {
      # Not required, but used in the example to access the nodes to inspect mounted volumes
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
  }
  eks_managed_node_groups = {
    #  We recommend to have a MNG to place your critical workloads and add-ons
    #  Then rely on Karpenter to scale your workloads
    #  You can also make uses on nodeSelector and Taints/tolerations to spread workloads on MNG or Karpenter provisioners
    core_node_group = {
      name                   = "${local.name}-core"
      create_iam_role        = false
      create_iam_role_policy = false
      description            = "EKS managed node group example launch template"
      iam_role_arn           = data.aws_iam_role.CoreNodeGroup.arn
      min_size               = 2
      max_size               = 5
      desired_size           = 3
      instance_types         = ["m5.xlarge"]

      ebs_optimized = true
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            encrypted             = true
            volume_size           = 100
            volume_type           = "gp3"
            delete_on_termination = true
          }
        }
      }
      network_interfaces = [{
        associate_public_ip_address = false
        # delete_on_termination       = true
        # device_index                = 0
        # security_groups = 
        # interface_type     = "interface"
        # network_card_index = 0
      }]
      # metadata_options = {
      #   http_endpoint               = "enabled"
      #   http_tokens                 = "required"
      #   http_put_response_hop_limit = 2
      #   instance_metadata_tags      = "disabled"
      # }
      labels = {
        WorkerType    = "${local.name}-ON_DEMAND"
        NodeGroupType = "${local.name}-core"
      }

      tags = {
        Name                     = "${local.name}-core-node-grp",
        "karpenter.sh/discovery" = local.name
        WorkerType               = "${local.name}-ON_DEMAND"
        NodeGroupType            = "${local.name}-core"
      }
    }
  }
  create_cloudwatch_log_group = false
  create_iam_role             = false
  create_kms_key              = false
  cluster_encryption_config   = {}
  outpost_config              = {}
  iam_role_arn                = data.aws_iam_role.ClusterRole.arn
  enable_irsa                 = true

  tags = local.tags
}
