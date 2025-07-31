# Terraform configuration for AWS infrastructure
# 6 RHEL VMs: 3 master control plane + 3 data plane nodes
# VPC: 10.122.0.0/16 with 6 subnets (3 public, 3 private) + 1 NAT Gateway

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data source for RHEL AMI
data "aws_ami" "rhel" {
  most_recent = true
  owners      = ["309956199498"] # Red Hat official account

  filter {
    name   = "name"
    values = ["RHEL-9.3*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# VPC
resource "aws_vpc" "kubernetes_vpc" {
  cidr_block           = "10.122.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "kubernetes-vpc"
    Environment = var.environment
    Project     = "kubernetes-cluster"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "kubernetes_igw" {
  vpc_id = aws_vpc.kubernetes_vpc.id

  tags = {
    Name        = "kubernetes-igw"
    Environment = var.environment
  }
}

# Public Subnets
resource "aws_subnet" "public_subnets" {
  count = 3

  vpc_id                  = aws_vpc.kubernetes_vpc.id
  cidr_block              = "10.122.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "public-subnet-${count.index + 1}"
    Environment = var.environment
    Type        = "Public"
  }
}

# Private Subnets
resource "aws_subnet" "private_subnets" {
  count = 3

  vpc_id            = aws_vpc.kubernetes_vpc.id
  cidr_block        = "10.122.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "private-subnet-${count.index + 1}"
    Environment = var.environment
    Type        = "Private"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name        = "kubernetes-nat-eip"
    Environment = var.environment
  }

  depends_on = [aws_internet_gateway.kubernetes_igw]
}

# NAT Gateway
resource "aws_nat_gateway" "kubernetes_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnets[0].id

  tags = {
    Name        = "kubernetes-nat-gateway"
    Environment = var.environment
  }

  depends_on = [aws_internet_gateway.kubernetes_igw]
}

# Route Tables
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.kubernetes_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.kubernetes_igw.id
  }

  tags = {
    Name        = "public-route-table"
    Environment = var.environment
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.kubernetes_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.kubernetes_nat.id
  }

  tags = {
    Name        = "private-route-table"
    Environment = var.environment
  }
}

# Route Table Associations
resource "aws_route_table_association" "public_rta" {
  count = 3

  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_rta" {
  count = 3

  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_rt.id
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Security Groups
resource "aws_security_group" "kubernetes_master_sg" {
  name_prefix = "kubernetes-master-"
  vpc_id      = aws_vpc.kubernetes_vpc.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Kubernetes API server
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["10.122.0.0/16"]
  }

  # etcd server client API
  ingress {
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = ["10.122.0.0/16"]
  }

  # Kubelet API
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["10.122.0.0/16"]
  }

  # kube-scheduler
  ingress {
    from_port   = 10259
    to_port     = 10259
    protocol    = "tcp"
    cidr_blocks = ["10.122.0.0/16"]
  }

  # kube-controller-manager
  ingress {
    from_port   = 10257
    to_port     = 10257
    protocol    = "tcp"
    cidr_blocks = ["10.122.0.0/16"]
  }

  # RKE2 server (supervisor port)
  ingress {
    from_port   = 9345
    to_port     = 9345
    protocol    = "tcp"
    cidr_blocks = ["10.122.0.0/16"]
  }

  # Calico BGP
  ingress {
    from_port   = 179
    to_port     = 179
    protocol    = "tcp"
    cidr_blocks = ["10.122.0.0/16"]
  }

  # Calico VXLAN
  ingress {
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    cidr_blocks = ["10.122.0.0/16"]
  }

  # Wireguard (Calico encryption)
  ingress {
    from_port   = 51820
    to_port     = 51821
    protocol    = "udp"
    cidr_blocks = ["10.122.0.0/16"]
  }

  # NodePort Services (for Rancher access)
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["10.122.0.0/16"]
  }

  # Rancher HTTP/HTTPS (load balancer access)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "kubernetes-master-sg"
    Environment = var.environment
  }
}

resource "aws_security_group" "kubernetes_worker_sg" {
  name_prefix = "kubernetes-worker-"
  vpc_id      = aws_vpc.kubernetes_vpc.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Kubelet API
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["10.122.0.0/16"]
  }

  # NodePort Services
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["10.122.0.0/16"]
  }

  # Calico BGP
  ingress {
    from_port   = 179
    to_port     = 179
    protocol    = "tcp"
    cidr_blocks = ["10.122.0.0/16"]
  }

  # Calico VXLAN
  ingress {
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    cidr_blocks = ["10.122.0.0/16"]
  }

  # Wireguard (Calico encryption)
  ingress {
    from_port   = 51820
    to_port     = 51821
    protocol    = "udp"
    cidr_blocks = ["10.122.0.0/16"]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "kubernetes-worker-sg"
    Environment = var.environment
  }
}

# Security Group for Ansible Control Node
resource "aws_security_group" "ansible_sg" {
  name        = "ansible-control-sg"
  description = "Security group for Ansible control node"
  vpc_id      = aws_vpc.kubernetes_vpc.id

  # SSH access from internet
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "ansible-control-sg"
    Environment = var.environment
  }
}

# Security Group for Load Balancer
resource "aws_security_group" "rancher_alb_sg" {
  name_prefix = "rancher-alb-"
  description = "Security group for Rancher Application Load Balancer"
  vpc_id      = aws_vpc.kubernetes_vpc.id

  # HTTP access from internet
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS access from internet
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound traffic to VPC (for health checks and forwarding)
  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.122.0.0/16"]
  }

  tags = {
    Name        = "rancher-alb-sg"
    Environment = var.environment
  }
}

# Use existing key pair (SMP-ANSIBLE already exists)
locals {
  key_name = var.aws_key_name
}

# Master Nodes (Control Plane) - Now in private subnets
resource "aws_instance" "kubernetes_masters" {
  count = 3

  ami                         = data.aws_ami.rhel.id
  instance_type              = var.master_instance_type
  key_name                   = local.key_name
  vpc_security_group_ids     = [aws_security_group.kubernetes_master_sg.id]
  subnet_id                  = aws_subnet.private_subnets[count.index].id
  associate_public_ip_address = false

  root_block_device {
    volume_type = "gp3"
    volume_size = 50
    encrypted   = true
  }

  # No user_data - minimal RHEL installation
  # All configuration will be done via Ansible

  tags = {
    Name        = "k8s-master-${count.index + 1}"
    Environment = var.environment
    Role        = "Master"
    Type        = "ControlPlane"
  }
}

# Worker Nodes (Data Plane)
resource "aws_instance" "kubernetes_workers" {
  count = 3

  ami                         = data.aws_ami.rhel.id
  instance_type              = var.worker_instance_type
  key_name                   = local.key_name
  vpc_security_group_ids     = [aws_security_group.kubernetes_worker_sg.id]
  subnet_id                  = aws_subnet.private_subnets[count.index].id
  associate_public_ip_address = false

  root_block_device {
    volume_type = "gp3"
    volume_size = 100
    encrypted   = true
  }

  # No user_data - minimal RHEL installation
  # All configuration will be done via Ansible

  tags = {
    Name        = "k8s-worker-${count.index + 1}"
    Environment = var.environment
    Role        = "Worker"
    Type        = "DataPlane"
  }
}

# RKE2 Server (Standalone Management Server)
resource "aws_instance" "rke2_server" {
  ami                         = data.aws_ami.rhel.id
  instance_type              = var.rke2_server_instance_type
  key_name                   = local.key_name
  vpc_security_group_ids     = [aws_security_group.kubernetes_master_sg.id]
  subnet_id                  = aws_subnet.private_subnets[0].id
  associate_public_ip_address = false

  root_block_device {
    volume_type = "gp3"
    volume_size = 60
    encrypted   = true
  }

  tags = {
    Name        = "rke2-server"
    Type        = "rke2-server"
    Environment = var.environment
    Role        = "RKE2-Management"
  }
}

# Ansible Control Node (Bastion Host)
resource "aws_instance" "ansible_control" {
  ami                         = data.aws_ami.rhel.id
  instance_type              = var.ansible_instance_type
  key_name                   = local.key_name
  vpc_security_group_ids     = [aws_security_group.ansible_sg.id]
  subnet_id                  = aws_subnet.public_subnets[0].id
  associate_public_ip_address = true
  
  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  tags = {
    Name        = "ansible-control"
    Type        = "ansible-control"
    Environment = var.environment
  }
}

# Application Load Balancer for Rancher
resource "aws_lb" "rancher_alb" {
  name               = "rancher-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.rancher_alb_sg.id]
  subnets            = aws_subnet.public_subnets[*].id

  enable_deletion_protection = false

  tags = {
    Name        = "rancher-alb"
    Environment = var.environment
  }
}

resource "aws_lb_target_group" "rancher_tg" {
  name     = "rancher-tg"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = aws_vpc.kubernetes_vpc.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/ping"
    port                = "traffic-port"
    protocol            = "HTTPS"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name        = "rancher-tg"
    Environment = var.environment
  }
}

# HTTP listener - redirect to HTTPS
resource "aws_lb_listener" "rancher_listener_http" {
  load_balancer_arn = aws_lb.rancher_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = {
    Name        = "rancher-listener-http"
    Environment = var.environment
  }
}

# HTTPS listener with SSL certificate
resource "aws_lb_listener" "rancher_listener_https" {
  load_balancer_arn = aws_lb.rancher_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = var.ssl_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rancher_tg.arn
  }

  tags = {
    Name        = "rancher-listener-https"
    Environment = var.environment
  }
}

resource "aws_lb_target_group_attachment" "rancher_targets" {
  count = 3

  target_group_arn = aws_lb_target_group.rancher_tg.id
  target_id        = aws_instance.kubernetes_masters[count.index].id
  port             = 443
}