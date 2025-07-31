# Output values for Terraform

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.kubernetes_vpc.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.kubernetes_vpc.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public_subnets[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private_subnets[*].id
}

output "ansible_control_public_ip" {
  description = "Public IP address of Ansible control node"
  value       = aws_instance.ansible_control.public_ip
}

output "ansible_control_private_ip" {
  description = "Private IP address of Ansible control node"
  value       = aws_instance.ansible_control.private_ip
}

output "rke2_server_private_ip" {
  description = "Private IP address of RKE2 server"
  value       = aws_instance.rke2_server.private_ip
}

output "master_private_ips" {
  description = "Private IP addresses of master nodes"
  value       = aws_instance.kubernetes_masters[*].private_ip
}

output "worker_private_ips" {
  description = "Private IP addresses of worker nodes"
  value       = aws_instance.kubernetes_workers[*].private_ip
}

output "master_instance_ids" {
  description = "Instance IDs of master nodes"
  value       = aws_instance.kubernetes_masters[*].id
}

output "worker_instance_ids" {
  description = "Instance IDs of worker nodes"
  value       = aws_instance.kubernetes_workers[*].id
}

output "rancher_load_balancer_dns" {
  description = "DNS name of the Rancher load balancer"
  value       = aws_lb.rancher_alb.dns_name
}

output "rancher_url" {
  description = "Complete Rancher URL with SSL"
  value       = "https://${var.domain_name}"
}

output "nat_gateway_ip" {
  description = "Elastic IP of the NAT Gateway"
  value       = aws_eip.nat_eip.public_ip
}

output "ansible_ssh_command" {
  description = "SSH command to connect to Ansible control node"
  value       = "ssh -i ~/.ssh/SMP-ANSIBLE.pem ec2-user@${aws_instance.ansible_control.public_ip}"
}

output "bastion_host_setup" {
  description = "Command to setup SSH bastion for private nodes"
  value = "ssh -i ~/.ssh/SMP-ANSIBLE.pem -J ec2-user@${aws_instance.ansible_control.public_ip} ec2-user@PRIVATE_IP"
}