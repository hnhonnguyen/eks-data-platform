variable "vpc_id" {
  default     = "vpc-07802c7ec880cc955"
  type        = string
  description = "This created vpc"
}

variable "subnet_ids" {
  default = ["subnet-0bf0b01ab1a0e8530", "subnet-001ab6642a2c79922"]
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
