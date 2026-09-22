# YAML-Driven Windows EC2 Terraform Module

A production-grade, highly configurable Terraform module to dynamically provision and manage **N** Windows Server EC2 instances on AWS, driven entirely by a single YAML configuration file (`config.yaml`).

---

## Key Features

- **Single Configuration File (`config.yaml`)**: Manage all infrastructure settings, instance sizing, storage, networking, and tags in one place.
- **Dynamic Sizing & Types**: Custom EC2 instance types (`t3.micro`, `t3.large`, `m5.2xlarge`, etc.) configurable globally and overridable per VM.
- **Smart Networking & Subnet Discovery**:
  - Automatically discovers subnets from your VPC if `public_subnet_ids: []` / `private_subnet_ids: []`.
  - Or manually specify subnets and distribute instances round-robin using `subnet_type: public` or `private`.
- **Automated RSA Key Pair Generation**:
  - Automatically creates a 4096-bit RSA key pair in AWS (`create_key_pair: true`).
  - Saves the private key to `./windows_key.pem` with secure read-only permissions (`0400`).
  - Or supports bringing an existing key pair via `key_name`.
- **Automated Secondary EBS Volume Management**:
  - Attach **N extra EBS disks** per VM (completely optional: 0 disks on VM 1, 1 disk on VM 2, multiple on VM 3).
  - Configurable volume sizes, volume types (`gp3`, `io2`, `gp2`), IOPS, throughput, encryption, and device names.
  - **100% Automated In-OS Disk Initialization**: An active background PowerShell watcher brings raw secondary disks online, initializes them with GPT, formats them with NTFS, and mounts them to drive letters (`E:`, `F:`, etc.) on first boot without manual intervention.
- **Security Groups & Ingress Control**: Auto-creates or attaches existing security groups, with customizable firewall rules (e.g. RDP port 3389 and WinRM ports 5985/5986).
- **Windows Password Decryption**: Instant retrieval and decryption of initial Windows Administrator passwords via AWS CLI and Terraform outputs.

---

## Repository Structure

```text
├── .gitignore             # Ignores .terraform/, state files, *.pem keys, and OS cache
├── config.yaml            # Main configuration file for all VMs and resources
├── main.tf                # Core logic: AMI lookup, EC2s, EBS volumes, SG, and key pair
├── variables.tf           # Terraform input variables and default fallbacks
├── provider.tf            # AWS, Random, TLS, and Local provider declarations
├── outputs.tf             # Rich outputs (IDs, IPs, subnets, password data, key path)
└── scripts/
    └── user_data.ps1      # PowerShell bootstrap script for WinRM, firewall, & auto-mount
```

---

## Quick Start

### 1. Prerequisites
- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) configured with valid AWS credentials
- Microsoft Remote Desktop (or any RDP client)

### 2. Configure `config.yaml`
Edit [`config.yaml`](config.yaml) to define your instances and settings:

```yaml
aws_region: us-east-1

# Optional VPC ID (null uses default VPC)
vpc_id: null

# Subnet Pools: leave empty [] for automatic discovery from your default VPC
public_subnet_ids: []
private_subnet_ids: []

# Security Group & Ingress Rules
create_security_group: true
security_group_ingress_rules:
  - from_port: 3389
    to_port: 3389
    protocol: tcp
    cidr_blocks: ["0.0.0.0/0"]
    description: "RDP"
  - from_port: 5985
    to_port: 5986
    protocol: tcp
    cidr_blocks: ["0.0.0.0/0"]
    description: "WinRM HTTP/HTTPS"

# Key Pair: auto-generate a fresh 4096-bit RSA key pair saved to windows_key.pem
key_name: null
create_key_pair: true

# Default instance settings
instance_type: t3.micro
windows_ami_name_pattern: "Windows_Server-2022-English-Full-Base*"
user_data_file: "scripts/user_data.ps1"

root_volume:
  size: 30
  type: gp3
  iops: 3000
  throughput: 125
  encrypted: true

# Define N Instances
instances:
  # VM 1: With 1 extra 10 GiB secondary disk
  - name: win-test-01
    subnet_type: public
    associate_public_ip: true
    instance_type: t3.micro
    root_volume:
      size: 30
      type: gp3
    extra_disks:
      - size: 10
        type: gp3
        device_name: /dev/sdf
    tags:
      Role: app-server

  # VM 2: Without extra disks (only C: drive)
  - name: win-test-02
    subnet_type: public
    associate_public_ip: true
    instance_type: t3.micro
    root_volume:
      size: 30
      type: gp3
    tags:
      Role: worker-server
```

### 3. Initialize & Deploy

```bash
# Initialize providers
terraform init

# Review execution plan
terraform plan

# Apply changes
terraform apply
```

---

## Connecting via RDP & Decrypting Passwords

### 1. View Outputs
After `terraform apply` finishes, retrieve the public IPs and key details:

```bash
terraform output public_ips
terraform output instances
```

### 2. Decrypt the Administrator Password
Terraform saves the private key file locally to `./windows_key.pem`. Use the AWS CLI to decrypt the password:

```bash
aws ec2 get-password-data \
  --instance-id <INSTANCE_ID> \
  --priv-launch-key windows_key.pem \
  --region us-east-1
```

### 3. Log In via RDP
Open Microsoft Remote Desktop on your machine:
- **PC Name**: `<PUBLIC_IP>`
- **Username**: `Administrator`
- **Password**: `<DECRYPTED_PASSWORD>`

---

## Configuration Reference

### Global Settings (`config.yaml`)

| Parameter | Type | Default | Description |
|---|---|---|---|
| `aws_region` | string | `us-east-1` | Target AWS region |
| `vpc_id` | string | `null` | Target VPC ID (default VPC if `null`) |
| `public_subnet_ids` | list | `[]` | Public subnets list (auto-discovered if `[]`) |
| `private_subnet_ids` | list | `[]` | Private subnets list (auto-discovered if `[]`) |
| `security_group_ids` | list | `[]` | Existing SGs to attach |
| `create_security_group` | bool | `true` | Auto-create security group |
| `security_group_ingress_rules` | list | RDP & WinRM | Ingress rules for the auto-created security group |
| `key_name` | string | `null` | Existing AWS Key Pair name |
| `create_key_pair` | bool | `true` | Generate RSA 4096 key pair and `./windows_key.pem` |
| `iam_instance_profile` | string | `null` | IAM instance profile name/ARN |
| `windows_ami_name_pattern` | string | `Windows_Server-2022-English-Full-Base*` | AMI search pattern |
| `windows_ami_owner` | string | `amazon` | AMI owner (`amazon`, `self`, or account ID) |
| `user_data_file` | string | `scripts/user_data.ps1` | Path to bootstrap script |
| `root_volume` | map | `{ size: 30, type: gp3 }` | Default root volume specification |
| `tags` | map | `{}` | Global tags applied to all resources |

### Per-Instance Settings (`instances[]`)

| Parameter | Type | Description |
|---|---|---|
| `name` | string | Unique instance identifier & Name tag |
| `instance_type` | string | Instance family/size override (`t3.micro`, `m5.large`, etc.) |
| `subnet_type` | string | `"public"` or `"private"` (picks from respective pool) |
| `subnet_id` | string | Direct subnet ID (overrides pool selection) |
| `associate_public_ip` | bool | Whether to assign a public IPv4 address |
| `security_group_ids` | list | Instance-specific security groups |
| `override_security_groups` | bool | If `true`, ignores global SGs and applies only instance SGs |
| `ami_id` | string | Specific AMI ID override for this instance |
| `root_volume` | map | Root volume override (`size`, `type`, `iops`, `throughput`, `encrypted`, `kms_key_id`) |
| `extra_disks` | list | Secondary EBS volumes (`size`, `type`, `iops`, `throughput`, `encrypted`, `device_name`) |
| `tags` | map | Custom instance tags (merged with global tags) |

---

## Clean Up

To tear down all resources provisioned by Terraform:

```bash
terraform destroy
```
