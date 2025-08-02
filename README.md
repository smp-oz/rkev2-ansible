# AWS RKE2 Kubernetes Cluster with Rancher

Production-ready RKE2 Kubernetes cluster deployment on AWS with unified master architecture and manual Rancher installation. This repository provides complete infrastructure automation and step-by-step Rancher setup for `rancher.smartcorex.com`.

## Architecture Overview (Updated January 31, 2025)

### Infrastructure Components  
- **3 Kubernetes Masters with RKE2**: Control plane nodes (10.122.10.76, 10.122.11.172, 10.122.12.175)
- **3 Kubernetes Workers**: Data plane nodes (10.122.10.159, 10.122.11.249, 10.122.12.215)
- **1 Ansible Controller**: Bastion host for secure access (3.17.155.172)
- **ALB**: Application Load Balancer for Rancher at rancher.smartcorex.com

### New Unified RKE2 Architecture

This system now uses a **unified RKE2 master architecture** for better reliability and simplified management:

#### Master Nodes with Integrated RKE2 (Control Plane) - 10.122.10.76, 10.122.11.172, 10.122.12.175
- **Primary Master (10.122.10.76)**: Initializes the cluster and generates tokens
- **Additional Masters**: Join as additional RKE2 servers for high availability
- **Functions**:
  - RKE2 cluster management (ETCD, API server, scheduler)
  - Pod scheduling and resource allocation
  - Service management and network routing
  - **Rancher UI runs on these master nodes**
  - Cluster token generation and certificate management

#### Kubernetes Worker Nodes (Data Plane) - 10.122.10.159, 10.122.11.249, 10.122.12.215
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
scp -i ~/.ssh/SMP-ANSIBLE.pem ~/.ssh/SMP-ANSIBLE.pem ec2-user@3.17.155.172:~/.ssh/
scp -i ~/.ssh/SMP-ANSIBLE.pem -r ansible/ ec2-user@3.17.155.172:~/

# SSH to controller and install Ansible
ssh -i ~/.ssh/SMP-ANSIBLE.pem ec2-user@3.17.155.172
chmod 600 ~/.ssh/SMP-ANSIBLE.pem

# Install Ansible on RHEL 9
sudo yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
sudo yum install -y ansible git python3-pip wget curl
ansible --version
```

### 3. Deploy RKE2 Cluster
```bash
cd ~/ansible

# Test connectivity to all nodes
ansible all -m ping

# Deploy complete RKE2 cluster (10-15 minutes)
ansible-playbook deploy-all.yml
```

### 4. Manual Rancher Installation

After RKE2 cluster is ready, follow these steps for Rancher installation:

#### Step 1: Configure kubectl and Install nginx-ingress
```bash
# SSH to RKE2 server
ssh -i ~/.ssh/SMP-ANSIBLE.pem ec2-user@3.133.147.25
ssh ec2-user@10.122.10.221
sudo su -

# Configure kubectl
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

# Verify cluster status
kubectl get nodes -o wide

# Add nginx-ingress repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install nginx-ingress with ALB-compatible configuration
helm install nginx-alb ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.ingressClassResource.name=nginx-alb \
  --set controller.ingressClass=nginx-alb \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.https=30443 \
  --set controller.service.nodePorts.http=30080 \
  --set controller.config.use-forwarded-headers=true \
  --set controller.config.compute-full-forwarded-for=true \
  --set controller.config.proxy-real-ip-cidr="10.122.0.0/16" \
  --wait --timeout=300s

# Verify nginx-ingress installation
kubectl get svc -n ingress-nginx
kubectl get pods -n ingress-nginx
```

#### Step 2: Install cert-manager
```bash
# Create cert-manager namespace
kubectl create namespace cert-manager

# Add cert-manager repository
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install cert-manager
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v1.13.0 \
  --set installCRDs=true \
  --wait \
  --timeout=10m

# Verify cert-manager
kubectl get pods -n cert-manager
```

#### Step 3: Install Rancher
```bash
# Create Rancher namespace
kubectl create namespace cattle-system

# Add Rancher repository
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update

# Create required TLS CA secret
kubectl create secret generic tls-ca \
  --from-literal=cacerts.pem="" \
  --namespace cattle-system

# IMPORTANT: Delete webhook validation to avoid timeout issues
kubectl delete validatingwebhookconfiguration nginx-alb-ingress-nginx-admission || true

# Install Rancher with nginx-alb ingress class
helm install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --set hostname=rancher.smartcorex.com \
  --set ingress.tls.source=secret \
  --set privateCA=true \
  --set ingress.ingressClassName=nginx-alb \
  --version=2.9.3 \
  --wait \
  --timeout=15m

# Verify Rancher installation
kubectl get pods -n cattle-system
kubectl get svc -n cattle-system
kubectl get ingress -n cattle-system
```

#### Step 4: Configure ALB Target Group
Update your AWS ALB target group to use NodePort 30443:

```bash
# Get the NodePort (should be 30443)
kubectl get svc nginx-alb-ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}'

# Update ALB target group to use port 30443 instead of 443
# Target Group Configuration:
# - Protocol: HTTPS
# - Port: 30443
# - Health Check Path: /healthz
# - Health Check Protocol: HTTP
# - Health Check Port: 30080
# - Targets: 10.122.10.46:30443, 10.122.11.81:30443, 10.122.12.28:30443
```

#### Step 5: Access Rancher
1. Wait 5-10 minutes for all pods to be ready
2. Access Rancher UI: https://rancher.smartcorex.com
3. Get initial password: `kubectl get secret --namespace cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}{{"\n"}}'`
4. Complete Rancher setup wizard

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
