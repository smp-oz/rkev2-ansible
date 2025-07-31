# Variables for Terraform configuration

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "aws_key_name" {
  description = "Name of existing AWS key pair"
  type        = string
  default     = "SMP-ANSIBLE"
}



variable "master_instance_type" {
  description = "Instance type for Kubernetes master nodes"
  type        = string
  default     = "t3.large"
}

variable "worker_instance_type" {
  description = "Instance type for Kubernetes worker nodes"
  type        = string
  default     = "t3.xlarge"
}

variable "ssl_certificate_arn" {
  description = "ARN of SSL certificate for load balancer"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Domain name for Rancher"
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "Kubernetes cluster name"
  type        = string
  default     = "production-cluster"
}

variable "ansible_instance_type" {
  description = "Instance type for Ansible control node"
  type        = string
  default     = "t3.medium"
}

variable "rke2_server_instance_type" {
  description = "Instance type for RKE2 server node"
  type        = string
  default     = "t3.large"
}