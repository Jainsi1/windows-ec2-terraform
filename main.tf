data "aws_ami" "windows" {
  most_recent = true
  filter {
    name   = "name"
    values = [local.global_ami_pattern]
  }
  owners = [local.global_ami_owner]
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id != null ? local.vpc_id : data.aws_vpc.default.id]
  }
}

resource "random_id" "sg_suffix" {
  byte_length = 2
}

# Auto-generate RSA 4096-bit Key Pair for Windows Administrator access
resource "tls_private_key" "windows_key" {
  count     = local.create_key_pair ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "windows_key" {
  count      = local.create_key_pair ? 1 : 0
  key_name   = "windows-ec2-key-${random_id.sg_suffix.hex}"
  public_key = tls_private_key.windows_key[0].public_key_openssh

  tags = merge({ Name = "windows-ec2-key" }, local.global_tags)
}

resource "local_file" "private_key" {
  count           = local.create_key_pair ? 1 : 0
  content         = tls_private_key.windows_key[0].private_key_pem
  filename        = "${path.module}/windows_key.pem"
  file_permission = "0400"
}

resource "aws_security_group" "instance_sg" {
  count       = local.create_sg && length(local.global_sg_ids) == 0 ? 1 : 0
  name        = "windows-ec2-sg-${random_id.sg_suffix.hex}"
  description = "Security group for Windows instances"
  vpc_id      = local.vpc_id

  dynamic "ingress" {
    for_each = local.effective_ingress_rules
    content {
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = try(ingress.value.cidr_blocks, ["0.0.0.0/0"])
      description = try(ingress.value.description, null)
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge({ Name = "windows-ec2-sg" }, local.global_tags)
}

locals {
  # Load YAML config from file
  cfg = yamldecode(file(var.config_file))

  # Networking & VPC
  vpc_id             = try(local.cfg.vpc_id, var.vpc_id)
  public_subnet_ids  = try(local.cfg.public_subnet_ids, var.public_subnet_ids)
  private_subnet_ids = try(local.cfg.private_subnet_ids, var.private_subnet_ids)
  flat_subnet_ids    = try(local.cfg.subnet_ids, var.subnet_ids)

  # Security Groups
  global_sg_ids    = try(local.cfg.security_group_ids, var.security_group_ids)
  create_sg        = try(local.cfg.create_security_group, var.create_security_group)
  sg_ingress_rules = try(local.cfg.security_group_ingress_rules, var.security_group_ingress_rules)

  default_ingress_rules = [
    {
      from_port   = 3389
      to_port     = 3389
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "RDP"
    },
    {
      from_port   = 5985
      to_port     = 5986
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "WinRM HTTP/HTTPS"
    }
  ]

  effective_ingress_rules = local.sg_ingress_rules != null ? local.sg_ingress_rules : local.default_ingress_rules
  created_sg_ids          = (local.create_sg && length(local.global_sg_ids) == 0) ? [aws_security_group.instance_sg[0].id] : []
  effective_global_sgs    = length(local.global_sg_ids) > 0 ? local.global_sg_ids : local.created_sg_ids

  # Key Pair: auto-create if create_key_pair is true or key_name is null/empty
  create_key_pair = try(local.cfg.create_key_pair, var.create_key_pair) || (try(local.cfg.key_name, null) == null || try(local.cfg.key_name, "") == "")
  global_key_name = local.create_key_pair ? aws_key_pair.windows_key[0].key_name : try(local.cfg.key_name, var.key_name)
  global_iam_profile     = try(local.cfg.iam_instance_profile, var.iam_instance_profile)
  global_ami_pattern     = try(local.cfg.windows_ami_name_pattern, var.windows_ami_name_pattern)
  global_ami_owner       = try(local.cfg.windows_ami_owner, var.windows_ami_owner)
  global_ami_id          = try(local.cfg.windows_ami_id, var.windows_ami_id)
  global_assoc_public_ip = try(local.cfg.associate_public_ip, var.associate_public_ip)
  global_user_data       = try(local.cfg.user_data, var.user_data)
  global_user_data_file  = try(local.cfg.user_data_file, var.user_data_file)
  global_tags            = try(local.cfg.tags, var.tags)

  # Global root volume defaults
  default_root_volume = {
    size       = try(local.cfg.root_volume.size, try(local.cfg.root_volume_size, var.root_volume_size))
    type       = try(local.cfg.root_volume.type, try(local.cfg.root_volume_type, var.root_volume_type))
    iops       = try(local.cfg.root_volume.iops, try(local.cfg.root_volume_iops, var.root_volume_iops))
    throughput = try(local.cfg.root_volume.throughput, try(local.cfg.root_volume_throughput, var.root_volume_throughput))
    encrypted  = try(local.cfg.root_volume.encrypted, try(local.cfg.root_volume_encrypted, var.root_volume_encrypted))
    kms_key_id = try(local.cfg.root_volume.kms_key_id, try(local.cfg.root_volume_kms_key_id, var.root_volume_kms_key_id))
  }

  # Global extra disks defaults (if any)
  global_extra_disks = try(local.cfg.extra_disks, var.extra_disks)

  # Instances source: if `instances` list is provided in YAML or var.instances, use it.
  # Otherwise dynamically generate N instances based on instance_count.
  raw_instances_list = coalescelist(
    try(local.cfg.instances, []),
    try(var.instances, []),
    [
      for i in range(try(local.cfg.instance_count, var.instance_count)) : {
        name = "windows-ec2-${i + 1}"
      }
    ]
  )

  # Device name letter pool for extra disks
  device_letters = ["f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p"]

  # Normalize each instance configuration with all defaults and overrides
  normalized_instances = {
    for idx, inst in local.raw_instances_list :
    (try(inst.name, null) != null && try(inst.name, "") != "" ? inst.name : "windows-ec2-${idx + 1}") => {
      index = idx
      name  = try(inst.name, null) != null && try(inst.name, "") != "" ? inst.name : "windows-ec2-${idx + 1}"

      instance_type = try(inst.instance_type, try(local.cfg.instance_type, var.instance_type))
      ami_id        = try(inst.ami_id, try(inst.ami, coalesce(local.global_ami_id, data.aws_ami.windows.id)))

      # Subnet selection:
      # 1. explicit inst.subnet_id
      # 2. if subnet_type == "public" or inst.public == true -> element(public_subnets)
      # 3. else if subnet_type == "private" or inst.public == false -> element(private_subnets)
      # 4. fallback: round-robin across private, public, or flat subnets
      subnet_id = coalesce(
        try(inst.subnet_id, null),
        (try(inst.subnet_type, "") == "public" || try(inst.public, false)) && length(local.public_subnet_ids) > 0 ?
        element(local.public_subnet_ids, idx % length(local.public_subnet_ids)) : null,
        (try(inst.subnet_type, "") == "private" || try(inst.public, null) == false) && length(local.private_subnet_ids) > 0 ?
        element(local.private_subnet_ids, idx % length(local.private_subnet_ids)) : null,
        length(local.public_subnet_ids) > 0 ?
        element(local.public_subnet_ids, idx % length(local.public_subnet_ids)) : null,
        length(local.private_subnet_ids) > 0 ?
        element(local.private_subnet_ids, idx % length(local.private_subnet_ids)) : null,
        length(local.flat_subnet_ids) > 0 ?
        element(local.flat_subnet_ids, idx % length(local.flat_subnet_ids)) : null,
        length(data.aws_subnets.default.ids) > 0 ?
        element(data.aws_subnets.default.ids, idx % length(data.aws_subnets.default.ids)) : null
      )

      # Associate public IP:
      associate_public_ip_address = try(
        inst.associate_public_ip,
        (try(inst.subnet_type, "") == "public" || try(inst.public, false)) ? true : local.global_assoc_public_ip
      )

      # Security groups:
      vpc_security_group_ids = distinct(concat(
        try(inst.override_security_groups, false) ? [] : local.effective_global_sgs,
        try(inst.security_group_ids, [])
      ))

      # Key name & IAM instance profile
      key_name             = try(inst.key_name, local.global_key_name)
      iam_instance_profile = try(inst.iam_instance_profile, local.global_iam_profile)

      # Root volume
      root_volume = {
        size       = try(inst.root_volume.size, try(inst.root_volume_size, local.default_root_volume.size))
        type       = try(inst.root_volume.type, try(inst.root_volume_type, local.default_root_volume.type))
        iops       = try(inst.root_volume.iops, try(inst.root_volume_iops, local.default_root_volume.iops))
        throughput = try(inst.root_volume.throughput, try(inst.root_volume_throughput, local.default_root_volume.throughput))
        encrypted  = try(inst.root_volume.encrypted, try(inst.root_volume_encrypted, local.default_root_volume.encrypted))
        kms_key_id = try(inst.root_volume.kms_key_id, try(inst.root_volume_kms_key_id, local.default_root_volume.kms_key_id))
      }

      # Extra disks:
      extra_disks = length(try(inst.extra_disks, [])) > 0 ? inst.extra_disks : (
        try(inst.extra_disk_count, 0) > 0 ? [
          for d_i in range(inst.extra_disk_count) : {
            size       = try(inst.extra_disk_size, 500)
            type       = try(inst.extra_disk_type, "gp3")
            iops       = try(inst.extra_disk_iops, null)
            throughput = try(inst.extra_disk_throughput, null)
            encrypted  = try(inst.extra_disk_encrypted, true)
            kms_key_id = try(inst.extra_disk_kms_key_id, null)
          }
        ] : local.global_extra_disks
      )

      # User data
      user_data = try(
        inst.user_data,
        try(file(inst.user_data_file), null),
        local.global_user_data,
        try(file(local.global_user_data_file), null),
        null
      )

      # Tags
      tags = merge(
        local.global_tags,
        { Name = try(inst.name, null) != null && try(inst.name, "") != "" ? inst.name : "windows-ec2-${idx + 1}" },
        try(inst.tags, {})
      )
    }
  }

  # Build flat map for extra EBS volumes
  extra_vol_list = flatten([
    for inst_key, inst in local.normalized_instances : [
      for d_idx, d in inst.extra_disks : {
        key          = "${inst_key}-disk-${d_idx + 1}"
        instance_key = inst_key
        disk_index   = d_idx
        size         = try(d.size, 500)
        type         = try(d.type, "gp3")
        iops         = try(d.iops, null)
        throughput   = try(d.throughput, null)
        encrypted    = try(d.encrypted, true)
        kms_key_id   = try(d.kms_key_id, null)
        device_name  = try(d.device_name, null) != null ? d.device_name : "/dev/sd${element(local.device_letters, d_idx % length(local.device_letters))}"
        tags         = merge(local.global_tags, { Name = "${inst_key}-disk-${d_idx + 1}" }, try(d.tags, {}))
      }
    ]
  ])

  extra_vol_map = { for v in local.extra_vol_list : v.key => v }
}

# Windows EC2 Instances
resource "aws_instance" "windows" {
  for_each = local.normalized_instances

  ami                         = each.value.ami_id
  instance_type               = each.value.instance_type
  subnet_id                   = each.value.subnet_id
  associate_public_ip_address = each.value.associate_public_ip_address
  vpc_security_group_ids      = each.value.vpc_security_group_ids
  key_name                    = each.value.key_name
  iam_instance_profile        = each.value.iam_instance_profile
  get_password_data           = each.value.key_name != null ? true : false
  user_data                   = each.value.user_data

  root_block_device {
    volume_size           = each.value.root_volume.size
    volume_type           = each.value.root_volume.type
    iops                  = contains(["gp3", "io1", "io2"], each.value.root_volume.type) ? each.value.root_volume.iops : null
    throughput            = each.value.root_volume.type == "gp3" ? each.value.root_volume.throughput : null
    encrypted             = each.value.root_volume.encrypted
    kms_key_id            = each.value.root_volume.kms_key_id
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "optional"
    http_put_response_hop_limit = 2
  }

  tags = each.value.tags

  lifecycle {
    ignore_changes = [
      get_password_data,
    ]
  }
}

# Extra EBS Volumes
resource "aws_ebs_volume" "extra" {
  for_each = local.extra_vol_map

  availability_zone = aws_instance.windows[each.value.instance_key].availability_zone
  size              = each.value.size
  type              = each.value.type
  iops              = contains(["gp3", "io1", "io2"], each.value.type) ? each.value.iops : null
  throughput        = each.value.type == "gp3" ? each.value.throughput : null
  encrypted         = each.value.encrypted
  kms_key_id        = each.value.kms_key_id

  tags = each.value.tags
}

# Volume Attachments
resource "aws_volume_attachment" "extra_attach" {
  for_each = local.extra_vol_map

  device_name = each.value.device_name
  instance_id = aws_instance.windows[each.value.instance_key].id
  volume_id   = aws_ebs_volume.extra[each.key].id
}
