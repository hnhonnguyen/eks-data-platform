data "aws_iam_role" "ClusterRole" {
  name = "vendor1-cluster-role"
}

data "aws_iam_role" "CoreNodeGroup" {
  name = "vendor1-core-eks-node-group-role"
}

data "aws_iam_role" "KarpenterNode" {
  name = "vendor1-karpenter-node-role"
}

data "aws_iam_role" "Karpenter" {
  name = "vendor1-karpenter-role"
}
