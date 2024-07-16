data "aws_iam_role" "ClusterRole" {
  name = "vendor1-service-role-cluster"
}

data "aws_iam_role" "CoreNodeGroup" {
  name = "vendor1-service-role-core-eks-node-group"
}

data "aws_iam_role" "KarpenterNode" {
  name = "vendor1-service-role-karpenter-node"
}

data "aws_iam_role" "Karpenter" {
  name = "vendor1-service-role-karpenter"
}
