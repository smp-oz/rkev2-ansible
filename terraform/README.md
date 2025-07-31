# Terraform Infrastructure

AWS RKE2 Kubernetes infrastructure için Terraform yapılandırması.

## Kullanım

### 1. Başlangıç Kurulumu
```bash
# Dependencies kur (Mac)
brew install terraform awscli

# AWS yapılandır
aws configure
```

### 2. Terraform Değişkenlerini Ayarla
```bash
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars

# Önemli: Ohio region (us-east-2) ve SMP-ANSIBLE key zaten ayarlanmış
# Sadece instance type'ları kontrol et
```

### 3. Infrastructure Deploy Et
```bash
# Terraform directory'de olduğundan emin ol
pwd  # /path/to/project/terraform olmalı
ls   # main.tf, user-data.sh, variables.tf dosyaları görünmeli

terraform init
terraform plan
terraform apply
```

### 4. Output'ları Al
```bash
# Master node public IP'leri
terraform output master_public_ips

# Master node private IP'leri  
terraform output master_private_ips

# Worker node private IP'leri
terraform output worker_private_ips

# Rancher load balancer DNS
terraform output rancher_load_balancer_dns
```

## Oluşturulan Kaynaklar

- **VPC**: 10.122.0.0/16 CIDR
- **Subnets**: 6 subnet (3 public, 3 private)
- **NAT Gateway**: Private subnet internet erişimi
- **Security Groups**: Production RKE2 and Calico CNI ports with encryption
- **EC2 Instances**: 3 master + 3 worker RHEL node (minimal kurulum)
- **Load Balancer**: Rancher UI erişimi için ALB

**Not**: EC2 instance'lar minimal RHEL ile kurulur, tüm konfigürasyon Ansible ile yapılır.

## Temizlik

```bash
terraform destroy
```

**Uyarı**: Bu komut tüm infrastructure'ı kalıcı olarak siler.