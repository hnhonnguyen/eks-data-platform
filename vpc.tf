variable "vpc_id" {
  default     = "vpc-02381b08951db92b5"
  type        = string
  description = "This created vpc"
}

variable "subnet_ids" {
  default = [
    "subnet-03589b20db544b118",
    "subnet-005a76641b441106a",
    # "subnet-047ed6ff2bb4afd21",
    # "subnet-08c505511f941f3bf"
  ]
}

data "aws_vpc" "vendor1" {
  id = var.vpc_id
}

data "aws_subnet" "eks_subnet" {
  count = length(var.subnet_ids)
  id    = var.subnet_ids[count.index]
}
output "eks_subnet" {
  value = data.aws_subnet.eks_subnet
}
