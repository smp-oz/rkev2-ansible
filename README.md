# AWS RKE2 Kubernetes Cluster with Rancher

Production-ready RKE2 Kubernetes cluster deployment on AWS with dedicated RKE2 server and Rancher management.

## Architecture

### Infrastructure Components
- **1 RKE2 Server**: Standalone management server for cluster orchestration
- **3 Kubernetes Masters**: Control plane nodes for high availability
- **3 Kubernetes Workers**: Data plane nodes for workload execution  
- **1 Ansible Controller**: Bastion host for secure private network access
- **ALB**: Application Load Balancer for Rancher access via rancher.smartcorex.com

### Network Design
- **VPC**: 10.122.0.0/16 CIDR block
- **Public Subnets**: 3 subnets for ALB and Ansible controller
- **Private Subnets**: 3 subnets for all Kubernetes nodes and RKE2 server
- **NAT Gateway**: Secure outbound internet access for private instances

## Deployment Guide

### Prerequisites
1. AWS CLI configured with appropriate permissions
2. Terraform >= 1.0 installed
3. SSH key pair (SMP-ANSIBLE) available in AWS and locally at ~/.ssh/SMP-ANSIBLE.pem
4. SSL certificate for rancher.smartcorex.com in ACM

### Step 1: Deploy Infrastructure
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform plan
terraform apply

# Note the outputs - you'll need these IP addresses:
# ansible_control_public_ip = "3.133.147.25"
# rke2_server_private_ip = "10.122.10.221"  
# master_private_ips = ["10.122.10.46", "10.122.11.81", "10.122.12.28"]
# worker_private_ips = ["10.122.10.83", "10.122.11.68", "10.122.12.203"]
```

### Step 2: Copy SSH Key and Files to Ansible Controller
```bash
# Copy your SSH private key to the Ansible controller
scp -i ~/.ssh/SMP-ANSIBLE.pem ~/.ssh/SMP-ANSIBLE.pem ec2-user@3.133.147.25:~/.ssh/

# Copy the entire ansible directory to the controller
scp -i ~/.ssh/SMP-ANSIBLE.pem -r ansible/ ec2-user@3.133.147.25:~/

# Alternatively, use rsync for better file synchronization
rsync -avz -e "ssh -i ~/.ssh/SMP-ANSIBLE.pem" ansible/ ec2-user@3.133.147.25:~/ansible/
```

### Step 3: Setup Ansible Controller
```bash
# SSH to Ansible controller
ssh -i ~/.ssh/SMP-ANSIBLE.pem ec2-user@3.133.147.25

# Set correct permissions for SSH key
chmod 600 ~/.ssh/SMP-ANSIBLE.pem

# Install Ansible and dependencies
sudo dnf update -y
sudo dnf install -y ansible git python3-pip

# Verify Ansible installation
ansible --version
```

### Step 4: Deploy RKE2 and Rancher
```bash
# Navigate to ansible directory
cd ~/ansible

# Test connectivity to all nodes
ansible all -m ping

# Run complete deployment
ansible-playbook deploy-all.yml

# Or run individual stages if needed:
# ansible-playbook playbooks/01-system-setup.yml
# ansible-playbook playbooks/02-rke2-server.yml
# ansible-playbook playbooks/03-k8s-nodes.yml
# ansible-playbook playbooks/04-rancher-install.yml
# ansible-playbook playbooks/05-cluster-verify.yml
```

### Step 5: Configure Load Balancer
The ALB target group needs to point to the Kubernetes masters for Rancher access:
- Target Group: rancher-tg
- Protocol: HTTPS
- Port: 443  
- Health Check: /ping
- Targets: All 3 Kubernetes master instances

### Step 6: Access Rancher
1. Navigate to https://rancher.smartcorex.com
2. Complete initial Rancher setup
3. Set admin password
4. Import existing cluster or create new workloads

## Deployment Scripts

### Individual Components
```bash
# System preparation only
ansible-playbook playbooks/01-system-setup.yml

# RKE2 server only  
ansible-playbook playbooks/02-rke2-server.yml

# Kubernetes nodes only
ansible-playbook playbooks/03-k8s-nodes.yml

# Rancher installation only
ansible-playbook playbooks/04-rancher-install.yml

# Cluster verification only
ansible-playbook playbooks/05-cluster-verify.yml
```

### Complete Deployment
```bash
# Deploy everything in sequence
ansible-playbook deploy-all.yml
```

### Specific Host Groups
```bash
# RKE2 server and Kubernetes masters only
ansible-playbook deploy-all.yml --limit rke2_server,k8s_masters

# Workers only  
ansible-playbook deploy-all.yml --limit k8s_workers
```

## Key Features

### Security
- All Kubernetes nodes in private subnets
- SELinux in permissive mode for container compatibility
- Encrypted EBS volumes
- Security groups with minimal required access
- SSL/TLS with Let's Encrypt certificates

### High Availability
- 3-master control plane for fault tolerance
- Multi-AZ deployment across availability zones
- Load balancer health checks and automatic failover
- Redundant networking with NAT gateway

### Management
- Dedicated RKE2 server for cluster management
- Rancher for centralized Kubernetes operations
- Ansible automation for consistent deployments
- Bastion host for secure private network access

## Troubleshooting

### Check Cluster Status
```bash
# On RKE2 server
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
/usr/local/bin/kubectl get nodes -o wide
/usr/local/bin/kubectl get pods -A
```

### Service Status
```bash
# On RKE2 server
systemctl status rke2-server

# On Kubernetes masters
systemctl status rke2-server

# On Kubernetes workers  
systemctl status rke2-agent
```

### Logs
```bash
# RKE2 server logs
journalctl -u rke2-server -f

# Kubernetes master logs
journalctl -u rke2-server -f

# Kubernetes worker logs
journalctl -u rke2-agent -f
```

## Clean Up
```bash
cd terraform
terraform destroy
```

This will remove all AWS resources created by Terraform.
