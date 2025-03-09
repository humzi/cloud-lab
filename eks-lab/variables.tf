variable "tags" {
  type = map(string)
  default = {
    Environment = "dev"
    Project     = "eks-cost-lab"
    Team        = "devops"
    CostCenter  = "12345"
  }
}

variable "instance_type" {
  type    = string
  default = "t3.medium"  # Right-size for non-prod
}