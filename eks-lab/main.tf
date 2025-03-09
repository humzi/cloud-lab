module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "eks-vpc"
  cidr = "10.0.0.0/16"
  azs  = ["eu-north-1a", "eu-north-1b"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  enable_nat_gateway = true
  single_nat_gateway = true

  tags = merge(var.tags, {
    "kubernetes.io/cluster/eks-cost-lab" = "shared"
  })
}

resource "aws_security_group_rule" "eks_api_access" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["185.113.96.206/32"]  # Replace with your IP or VPC CIDR
  security_group_id = module.eks.cluster_security_group_id
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  # Allow public access to the EKS API endpoint
  cluster_endpoint_public_access = true
  cluster_endpoint_public_access_cidrs = ["185.113.96.206/32"]  # Restrict to your IP
  cluster_endpoint_private_access = false

  cluster_name    = "eks-cost-lab"
  cluster_version = "1.28"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  fargate_profiles = {
    spot = {
      name = "fargate-spot"
      selectors = [{ namespace = "fargate" }]
      capacity_provider = "FARGATE_SPOT"  # 70% savings
    }
  }

  tags = {
    Project = "eks-cost-lab"
  }
}

resource "null_resource" "wait_for_eks" {
  triggers = {
    cluster_arn = module.eks.cluster_arn  # Re-run if cluster changes
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for EKS cluster to be ready..."
      aws eks wait cluster-active --name ${module.eks.cluster_name} --region eu-north-1
      echo "Cluster is ready!"
    EOT
  }
}
resource "kubernetes_namespace" "fargate" {
  metadata {
    name = "fargate"
  }

  depends_on = [
    module.eks.cluster_id,
    null_resource.wait_for_eks
  ]
}


resource "kubernetes_deployment" "nginx" {
  metadata {
    name      = "nginx"
    namespace = kubernetes_namespace.fargate.metadata[0].name
  }
  spec {
    replicas = 2
    selector { match_labels = { app = "nginx" } }
    template {
      metadata { labels = { app = "nginx" } }
      spec {
        container {
          name  = "nginx"
          image = "nginx:latest"
          port { container_port = 80 }
        }
      }
    }
  }
}

resource "kubernetes_service" "nginx" {
  metadata {
    name      = "nginx-service"
    namespace = kubernetes_namespace.fargate.metadata[0].name
    annotations = {
      # Tag the ALB for cost tracking
      "service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags" = "Project=eks-cost-lab"
    }
  }
  spec {
    selector = { app = "nginx" }
    port { port = 80 }
    type = "LoadBalancer"  # Creates an AWS ALB
  }
}