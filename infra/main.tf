locals {
  name_prefix = "caprakurs"
  tags = {
    project = "${local.name_prefix}-k8s"
  }
  key_name        = "${local.name_prefix}-pk"
  number_of_nodes = 3
}


resource "tls_private_key" "kurs_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = local.key_name
  public_key = tls_private_key.kurs_key.public_key_openssh
}

output "pubkey" {
  value = aws_key_pair.generated_key.public_key
}

resource "aws_vpc" "this" {
  cidr_block = "10.10.0.0/16"

  enable_dns_hostnames = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
}

resource "aws_security_group" "instance_security" {
  name = "${local.name_prefix}-sg"

  vpc_id = aws_vpc.this.id
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "all"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "all"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_route_table_association" "public" {
  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.public.id
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = "eu-west-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-subnet"
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["amazon"] # Canonical
}

# Create IAM Role
resource "aws_iam_role" "ssm_role" {
  name = "${local.name_prefix}-ec2-roles"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Attach AmazonSSMManagedInstanceCore Policy to the Role
resource "aws_iam_role_policy_attachment" "ssm_policy_attachment" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Create IAM Instance Profile
resource "aws_iam_instance_profile" "ssm_instance_profile" {
  name = "SSMInstanceProfile"
  role = aws_iam_role.ssm_role.name
}

resource "aws_instance" "nodes" {
  for_each = toset([for k in range(local.number_of_nodes) : tostring(k)])

  vpc_security_group_ids = [aws_security_group.instance_security.id]

  key_name                    = aws_key_pair.generated_key.key_name
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.medium"
  subnet_id                   = aws_subnet.public.id
  iam_instance_profile        = aws_iam_instance_profile.ssm_instance_profile.name
  associate_public_ip_address = true

  tags = {
    Name = "${local.name_prefix}-node${each.value}"
  }
}

output "private_key" {
  value     = tls_private_key.kurs_key.private_key_pem
  sensitive = true
}

resource "local_sensitive_file" "priv_pem_key" {
  filename             = "kurs_priv.pem"
  directory_permission = "700"
  file_permission      = "600"
  content              = tls_private_key.kurs_key.private_key_pem
}

output "dns" {
  value = jsonencode({
    "nodes" : [for node in aws_instance.nodes : node.public_dns]
  })
}

resource "local_file" "dns" {
  depends_on = [aws_instance.nodes]

  filename = "dns.json"
  content  = jsonencode({
    "nodes" : {for k, node in aws_instance.nodes : node.tags.Name => node.public_dns}
  })
}