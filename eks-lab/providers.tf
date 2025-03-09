terraform {
  backend "s3" {
    bucket = "cloud-lab-humzi"
    key = "terraform.tfstate"
    region = "eu-north-1"
  }
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.23" }
    kubectl = { source = "gavinbunney/kubectl", version = "~> 1.14" }
  }
}

provider "aws" {
  region = "eu-north-1"
  default_tags { tags = var.tags }  # Apply tags globally
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}