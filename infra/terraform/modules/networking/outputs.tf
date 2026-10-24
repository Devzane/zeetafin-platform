output "vpc_id" {
  description = "ID of the VPC. Passed to the ec2_server module to scope the security group."
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "ID of the public subnet. The EC2 instance is launched here."
  value       = aws_subnet.public.id
}

output "internet_gateway_id" {
  description = "ID of the internet gateway. Exposed for reference and debugging."
  value       = aws_internet_gateway.main.id
}

output "vpc_cidr_block" {
  description = "The VPC CIDR. Useful for security group ingress rules that reference the VPC range."
  value       = aws_vpc.main.cidr_block
}
