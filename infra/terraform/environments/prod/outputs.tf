output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.main.id
}

output "public_ip" {
  description = "Public IP of the EC2 instance. Changes on stop/start if no EIP is used."
  value       = aws_instance.main.public_ip
}

output "ssh_command" {
  description = "Copy-paste SSH command to connect to the instance."
  value       = "ssh -i ~/.ssh/phase1-key ubuntu@${aws_instance.main.public_ip}"
}

output "ami_id" {
  description = "AMI ID resolved by the data source. Record this for reproducibility."
  value       = data.aws_ami.ubuntu.id
}

output "ami_name" {
  description = "Human-readable AMI name — confirms Ubuntu 24.04 was selected."
  value       = data.aws_ami.ubuntu.name
}
