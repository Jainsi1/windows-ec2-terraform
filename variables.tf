variable "config_file" {
  description = "Path to the YAML configuration file"
  type        = string
  default     = "config.yaml"
}

variable "aws_region" {
  description = "AWS region to deploy resources into (overridden by config.yaml if set)"
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "VPC ID where security groups and instances belong (optional)"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "General list of subnet IDs (fallback when public/private subnets are not split)"
  type        = list(string)
  default     = []
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for internet-facing instances"
  type        = list(string)
  default     = []
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for internal instances"
  type        = list(string)
  default     = []
}

variable "associate_public_ip" {
  description = "Default public IP association setting"
  type        = bool
  default     = false
}

variable "security_group_ids" {
  description = "List of existing security group IDs to attach to instances"
  type        = list(string)
  default     = []
}

variable "create_security_group" {
  description = "Whether to create a default security group if security_group_ids is empty"
  type        = bool
  default     = true
}

variable "security_group_ingress_rules" {
  description = "Custom ingress rules for the auto-created security group"
  type        = any
  default     = null
}

variable "instance_count" {
  description = "Default count of instances when explicit instances list is omitted"
  type        = number
  default     = 1
}

variable "instance_type" {
  description = "Default EC2 instance type (e.g., t3.large, m5.xlarge)"
  type        = string
  default     = "t3.large"
}

variable "create_key_pair" {
  description = "Whether to automatically generate a new RSA 4096-bit key pair if key_name is null or empty"
  type        = bool
  default     = true
}

variable "key_name" {
  description = "Name of EC2 key pair for Windows Administrator password decryption"
  type        = string
  default     = null
}

variable "iam_instance_profile" {
  description = "IAM instance profile name/ARN to attach to instances (e.g. for SSM Agent)"
  type        = string
  default     = null
}

variable "windows_ami_id" {
  description = "Specific Windows AMI ID (if set, overrides AMI pattern search)"
  type        = string
  default     = null
}

variable "windows_ami_name_pattern" {
  description = "AMI name pattern to search for Windows AMIs from Amazon"
  type        = string
  default     = "Windows_Server-2022-English-Full-Base*"
}

variable "windows_ami_owner" {
  description = "Owner of the Windows AMI (e.g., 'amazon', 'self', or an AWS Account ID)"
  type        = string
  default     = "amazon"
}

variable "root_volume_size" {
  description = "Default root EBS volume size in GiB"
  type        = number
  default     = 100
}

variable "root_volume_type" {
  description = "Default root EBS volume type (gp3, io2, gp2, etc.)"
  type        = string
  default     = "gp3"
}

variable "root_volume_iops" {
  description = "Default IOPS for root volume (gp3/io1/io2)"
  type        = number
  default     = 3000
}

variable "root_volume_throughput" {
  description = "Default throughput in MiB/s for gp3 root volume"
  type        = number
  default     = 125
}

variable "root_volume_encrypted" {
  description = "Whether root volume should be encrypted"
  type        = bool
  default     = true
}

variable "root_volume_kms_key_id" {
  description = "KMS Key ARN or ID for EBS volume encryption"
  type        = string
  default     = null
}

variable "extra_disks" {
  description = "Global extra disks to attach to all instances unless overridden"
  type        = any
  default     = []
}

variable "extra_disk_count" {
  description = "Legacy fallback: number of extra disks"
  type        = number
  default     = 0
}

variable "extra_disk_size" {
  description = "Legacy fallback: size of each extra disk in GiB"
  type        = number
  default     = 500
}

variable "extra_disk_type" {
  description = "Legacy fallback: type of extra disk"
  type        = string
  default     = "gp3"
}

variable "user_data" {
  description = "Default user data script content for instances"
  type        = string
  default     = null
}

variable "user_data_file" {
  description = "Default path to a user data script file"
  type        = string
  default     = null
}

variable "tags" {
  description = "Default map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "instances" {
  description = "List of instance configurations (overridden by instances in config.yaml if present)"
  type        = any
  default     = []
}
