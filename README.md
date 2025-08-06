# AWS RKE2 Kubernetes Cluster with Rancher

Production-ready RKE2 Kubernetes cluster deployment on AWS with unified master architecture and manual Rancher installation. This repository provides complete infrastructure automation and step-by-step Rancher setup for `rancher.smartcorex.com`.

## Architecture Overview (Updated August 2, 2025)

## IP Address Management

### Current Infrastructure IPs
**Masters:**
- master-1: 10.122.10.68 (Primary)
- master-2: 10.122.11.60
- master-3: 10.122.12.162

**Workers:**
- worker-1: 10.122.10.211
- worker-2: 10.122.11.84
- worker-3: 10.122.12.58

**Ansible Controller:**
- Private: 10.122.1.35
- Public: 18.118.207.128

### When IPs Change (Cost Management)
When recreating AWS infrastructure, update:
1. `ansible/inventory/hosts.yml` - All node IPs
2. `ansible/playbooks/04-alb-setup.yml` - Master node list
3. `README.md` - Connection examples
4. `replit.md` - Architecture section

## IP Address Update Guide

### When AWS Infrastructure is Recreated

When you recreate the AWS infrastructure to save costs, IP addresses change. Here's what needs to be updated:

#### Files to Update After Infrastructure Recreation

**A. Ansible Inventory** (`ansible/inventory/hosts.yml`)
Update sections:
```yaml
k8s_masters:
  hosts:
    master-1:
      ansible_host: NEW_MASTER_1_IP  # ← UPDATE
    master-2:
      ansible_host: NEW_MASTER_2_IP  # ← UPDATE  
    master-3:
      ansible_host: NEW_MASTER_3_IP  # ← UPDATE

k8s_workers:
  hosts:
    worker-1:
      ansible_host: NEW_WORKER_1_IP # ← UPDATE
    worker-2:
      ansible_host: NEW_WORKER_2_IP # ← UPDATE
    worker-3:
      ansible_host: NEW_WORKER_3_IP # ← UPDATE

vars:
  rke2_server_ip: NEW_PRIMARY_MASTER_IP   # ← UPDATE (Primary master)
```

**B. Update Documentation Files**
- `replit.md` - Update architecture section with new IPs
- `README.md` - Update connection examples

#### Quick Update Commands

```bash
# Get new IPs from Terraform output
terraform output

# Update inventory file
vim ansible/inventory/hosts.yml

# Update documentation
vim replit.md README.md

# Test connectivity
ansible all -m ping

# Verify SSH access to new bastion IP
ssh -i ~/.ssh/SMP-ANSIBLE.pem ec2-user@NEW_BASTION_PUBLIC_IP
```

### On-Premises Deployment (Without PEM Keys)

For deploying to on-premises servers without AWS PEM keys:

#### 1. SSH Key Setup
```bash
# Generate SSH key pair
ssh-keygen -t rsa -b 4096 -f ~/.ssh/onprem_rke2

# Copy to all nodes
ssh-copy-id -i ~/.ssh/onprem_rke2.pub root@YOUR_NODE_IP
```

#### 2. Create On-Premises Inventory
Copy `ansible/inventory/hosts.yml` to `hosts-onprem.yml`:
```yaml
# Update with your network IPs and remove PEM key references
ansible_host: 192.168.1.10  # Your IPs
ansible_user: root          # Your user
ansible_ssh_private_key_file: ~/.ssh/onprem_rke2
# Remove ansible_ssh_private_key_file line for password auth
```

#### 3. Network Requirements
Configure firewall ports:
- **Masters**: 6443, 9345, 10250, 2379-2380
- **Workers**: 10250, 10251
- **NodePort**: 30000-32767
- **Flannel**: 8472/UDP

**Example firewalld commands:**
```bash
# On all nodes
firewall-cmd --permanent --add-port=10250/tcp
firewall-cmd --permanent --add-port=8472/udp

# On masters only
firewall-cmd --permanent --add-port=6443/tcp
firewall-cmd --permanent --add-port=9345/tcp
firewall-cmd --permanent --add-port=2379-2380/tcp

# On workers for NodePort services
firewall-cmd --permanent --add-port=30000-32767/tcp

firewall-cmd --reload
```

#### 4. DNS Configuration (On-Premises)
Update `/etc/hosts` or internal DNS:
```bash
# Add to /etc/hosts on all nodes
192.168.1.10    master-1 rancher.yourdomain.com
192.168.1.11    master-2
192.168.1.12    master-3
192.168.1.20    worker-1
192.168.1.21    worker-2
192.168.1.22    worker-3
```

#### 5. Deploy
```bash
# Use custom inventory
ansible-playbook -i ansible/inventory/hosts-onprem.yml ansible/playbooks/deploy-complete-k8s-rancher.yml
```

### Infrastructure Components (Updated August 6, 2025)
- **3 Kubernetes Masters with RKE2**: Control plane nodes (10.122.10.68, 10.122.11.60, 10.122.12.162)
- **3 Kubernetes Workers**: Data plane nodes (10.122.10.211, 10.122.11.84, 10.122.12.58)
- **1 Ansible Controller**: Bastion host for secure access (10.122.1.35 / Public: 18.118.207.128)
- **ALB**: Application Load Balancer for Rancher at rancher.smartcorex.com (rancher-alb-970471551.us-east-2.elb.amazonaws.com)

### New Unified RKE2 Architecture

This system now uses a **unified RKE2 master architecture** for better reliability and simplified management:

#### Master Nodes with Integrated RKE2 (Control Plane) - 10.122.10.68, 10.122.11.60, 10.122.12.162
- **Primary Master (10.122.10.68)**: Initializes the cluster and generates tokens
- **Additional Masters**: Join as additional RKE2 servers for high availability
- **Functions**:
  - RKE2 cluster management (ETCD, API server, scheduler)
  - Pod scheduling and resource allocation
  - Service management and network routing
  - **Rancher UI runs on these master nodes**
  - Cluster token generation and certificate management

#### Kubernetes Worker Nodes (Data Plane) - 10.122.10.211, 10.122.11.84, 10.122.12.58
- **Purpose**: Runs actual applications and workloads
- **Connection**: Joins cluster using token from primary master
- **Functions**:
  - Container execution (Docker, containerd)
  - Network routing and pod communication
  - Storage mount and volume management

### Network Design
- **VPC**: 10.122.0.0/16 CIDR block
- **Public Subnets**: 3 subnets for ALB and Ansible controller
- **Private Subnets**: 3 subnets for all Kubernetes nodes and RKE2 server
- **NAT Gateway**: Secure outbound internet access for private instances

## Quick Start

### Prerequisites
- AWS CLI configured with appropriate permissions
- Terraform >= 1.0 installed
- SSH key pair (SMP-ANSIBLE) available in AWS and locally at ~/.ssh/SMP-ANSIBLE.pem
- SSL certificate for rancher.smartcorex.com in ACM

### 1. Deploy Infrastructure
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values
terraform init
terraform plan
terraform apply
```

### 2. Setup Ansible Controller
```bash
# Copy SSH key and ansible directory
scp -i ~/.ssh/SMP-ANSIBLE.pem ~/.ssh/SMP-ANSIBLE.pem ec2-user@18.118.207.128:~/.ssh/
scp -i ~/.ssh/SMP-ANSIBLE.pem -r ansible/ ec2-user@18.118.207.128:~/

# SSH to controller and install Ansible
ssh -i ~/.ssh/SMP-ANSIBLE.pem ec2-user@18.118.207.128
chmod 600 ~/.ssh/SMP-ANSIBLE.pem

# Install Ansible on RHEL 9
sudo yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
sudo yum install -y ansible git python3-pip wget curl
ansible --version
```

### 3. Deploy Complete Cluster with Single Playbook
```bash
cd ~/ansible

# Test connectivity to all nodes
ansible all -m ping

# Deploy everything: K8s + Rancher + SSL + Ingress (30-45 minutes)
ansible-playbook ansible/playbooks/deploy-complete-k8s-rancher.yml
```

### 4. Configure ALB and Access Rancher

After deployment completes, run the ALB registration script:

```bash
# On the ansible controller (or any machine with AWS CLI configured)
bash /tmp/register_alb_targets.sh
```

#### Access Rancher UI
```bash
# Get the bootstrap password
kubectl get secret --namespace cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}'

# Access Rancher at
https://rancher.smartcorex.com
# Default username: admin
# Password: admin (or the bootstrap password above)
```

#### Verify Deployment
```bash
# Run the verification script
bash /tmp/verify_cluster.sh
```

## Current Infrastructure Status

**Deployed Infrastructure:**
- **Ansible Controller**: 3.133.147.25 (public), 10.122.1.228 (private)
- **RKE2 Server**: 10.122.10.221 (standalone management)
- **Kubernetes Masters**: 10.122.10.46, 10.122.11.81, 10.122.12.28
- **Kubernetes Workers**: 10.122.10.83, 10.122.11.68, 10.122.12.203
- **Load Balancer**: rancher-alb-1875712086.us-east-2.elb.amazonaws.com

**Current Status:**
- ✅ RKE2 Server installation and configuration
- ✅ 6 Kubernetes nodes joined cluster (3 masters + 3 workers)
- ✅ Helm installation and configuration
- ✅ nginx-ingress controller with ALB integration
- ✅ Rancher installation with proper ingress class
- ✅ ALB configured with NodePort 30443
- ✅ Rancher UI accessible at https://rancher.smartcorex.com

## Deployment Scripts

### Individual Components
```bash
# System preparation only
ansible-playbook playbooks/01-system-setup.yml

# RKE2 server only
ansible-playbook playbooks/02-rke2-server.yml

# Kubernetes nodes only
ansible-playbook playbooks/03-k8s-nodes.yml

# ALB setup only
ansible-playbook playbooks/04-alb-setup.yml

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
- SSL/TLS with self-signed certificates (upgradeable to Let's Encrypt)

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

### Common Issues and Fixes

**Rancher Pods Not Ready (0/1)**
```bash
# Check pod logs
kubectl logs -n cattle-system -l app=rancher

# Verify TLS secret exists
kubectl get secret tls-ca -n cattle-system

# Check ingress configuration
kubectl describe ingress rancher -n cattle-system
```

**503 Service Unavailable from ALB**
```bash
# Verify nginx-ingress is running
kubectl get pods -n ingress-nginx

# Check NodePort configuration
kubectl get svc nginx-alb-ingress-nginx-controller -n ingress-nginx

# Test health endpoint
curl -k http://10.122.10.46:30080/healthz
```

**Webhook Validation Timeouts**
```bash
# Delete problematic webhook configurations
kubectl delete validatingwebhookconfiguration nginx-alb-ingress-nginx-admission

# Restart Rancher installation
helm uninstall rancher -n cattle-system
helm install rancher rancher-stable/rancher [... with same parameters]
```

**Connectivity Issues**
```bash
# Test individual node groups
ansible rke2_server -m ping
ansible k8s_masters -m ping
ansible k8s_workers -m ping

# Manual SSH test
ssh -i ~/.ssh/SMP-ANSIBLE.pem ec2-user@10.122.10.221
```

**Service Status Checks**
```bash
# Check RKE2 services
ansible rke2_server -m shell -a "systemctl status rke2-server"
ansible k8s_masters -m shell -a "systemctl status rke2-server"
ansible k8s_workers -m shell -a "systemctl status rke2-agent"
```

**Cluster Status**
```bash
# From RKE2 server
ansible rke2_server -m shell -a "export KUBECONFIG=/etc/rancher/rke2/rke2.yaml && /usr/local/bin/kubectl get nodes -o wide"
```

## Architecture Benefits

### Dedicated RKE2 Server Advantages
- **Security**: Critical operations isolated on dedicated server
- **Management**: Centralized control point for easy backup and restore
- **Scalability**: New master/worker nodes can be easily added
- **Reliability**: RKE2 server can be independently managed and backed up
- **Performance**: Workload distribution can be optimized

### Manual Rancher Installation Benefits
- **Control**: Full visibility into installation process and configuration
- **Troubleshooting**: Easy to debug and fix issues step by step
- **Customization**: Flexible configuration for specific requirements
- **Reliability**: Avoids complex automation edge cases

## Clean Up
```bash
cd terraform
terraform destroy
```

This will remove all AWS resources created by Terraform.

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review logs using kubectl and ansible commands
3. Verify ALB target group configuration
4. Ensure all pods are in Running status before accessing Rancher UI
