output "instances" {
  description = "Detailed map of all created Windows EC2 instances"
  value = {
    for k, inst in aws_instance.windows : k => {
      id                = inst.id
      arn               = inst.arn
      name              = try(inst.tags["Name"], k)
      instance_type     = inst.instance_type
      private_ip        = inst.private_ip
      public_ip         = inst.public_ip
      subnet_id         = inst.subnet_id
      availability_zone = inst.availability_zone
      security_groups   = inst.vpc_security_group_ids
      key_name          = inst.key_name
    }
  }
}

output "instance_ids" {
  description = "List of all created Windows EC2 instance IDs"
  value       = [for inst in aws_instance.windows : inst.id]
}

output "public_ips" {
  description = "List of public IPs assigned to Windows instances (if any)"
  value       = compact([for inst in aws_instance.windows : inst.public_ip])
}

output "private_ips" {
  description = "List of private IPs assigned to Windows instances"
  value       = [for inst in aws_instance.windows : inst.private_ip]
}

output "security_group_id" {
  description = "ID of auto-created security group (if created)"
  value       = length(aws_security_group.instance_sg) > 0 ? aws_security_group.instance_sg[0].id : null
}

output "extra_volume_ids" {
  description = "Map of all extra EBS volume IDs created"
  value       = { for k, vol in aws_ebs_volume.extra : k => vol.id }
}

output "password_data" {
  description = "Base64 encoded encrypted password data for instances (decrypt using key pair private key)"
  value       = { for k, inst in aws_instance.windows : k => inst.password_data if inst.password_data != "" && inst.password_data != null }
}

output "key_name" {
  description = "EC2 Key Pair name used for Windows instances"
  value       = local.global_key_name
}

output "private_key_file" {
  description = "Path to the generated private key file (if auto-generated)"
  value       = local.create_key_pair ? "${path.module}/windows_key.pem" : null
}
