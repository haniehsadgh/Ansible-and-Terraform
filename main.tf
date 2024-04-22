# Haniehsadat Gholamhosseini

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# define the aws region to deploy resources
variable "aws_region" {
  description = "the aws region to deploy resources"
  default     = "us-west-2"
  type        = string
}

#Define ec2 type variable
variable "instance_type" {
  description = "instance type for the ec2 instances"
  default     = "t2.micro"
  type        = string
}

# Attributes for the ec2 instances to create
variable "ec2_instances" {
  type = map(object({
    server_type = string
  }))
  description = "ec2 instances configuration data, with instance name as key and server_type as only attribute"
  default = {
    "web01" : { server_type = "web" },
    "web02" : { server_type = "web" }
  }
}

# Define local variables
locals {
  base_cidr_block   = "10.0.0.0/16"
  subnet_cidr_block_a = "10.0.1.0/24"
  subnet_cidr_block_b = "10.0.2.0/24"
  project_name      = "acit4640_as2"
  availability_zone_a = "us-west-2a"
  availability_zone_b = "us-west-2b"
  ssh_key_name      = "demo_key"
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      project = "${local.project_name}"
    }
  }
}

module "ec2_module" {
  source  = ./modules/ec2_module
  project_name = local.project_name
  subnet_ids = aws_subnet.main_a[*].id
  security_groups = [aws_security_group.main.id]
  vpc_id = aws_vpc.main.id
  key_name = local.ssh_key_name
}

# Create a VPC
resource "aws_vpc" "main" {
  cidr_block     = local.base_cidr_block
  instance_tenancy       = "default"
  enable_dns_hostnames = true
  tags   = {
    name = "${local.project_name}_vpc"
  }
}

# Creare a public subnet
resource "aws_subnet" "main_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.subnet_cidr_block_a
  availability_zone       = local.availability_zone_a
  map_public_ip_on_launch = true
  tags = {
    name = "${local.project_name}_main_subnet_a"
  }
}

# Create another public subnet
resource "aws_subnet" "main_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.subnet_cidr_block_b
  availability_zone       = local.availability_zone_b
  map_public_ip_on_launch = true

  tags = {
    name = "${local.project_name}_main_subnet_b"
  }
}

#Setup the network infrastructure: internet gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    name = "${local.project_name}_main_igw"
  }
}

# Create a routing table
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    name = "${local.project_name}_main_rt"
  }
}

# Provides a resource to create a routing table entry (a route) in a VPC routing table.
resource "aws_route" "default_route" {
  route_table_id         = aws_route_table.main.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

# Associate the public subnets to the same routing table
resource "aws_route_table_association" "main_a" {
  subnet_id      = aws_subnet.main_a.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "main_b" {
  subnet_id      = aws_subnet.main_b.id
  route_table_id = aws_route_table.main.id
}

# Setup the security group for instances!
resource "aws_security_group" "main" {
  name           = "${local.project_name}_main_sg"
  description = "allow all outbound traffic and ssh and http in from everywhere"
  vpc_id         = aws_vpc.main.id
  tags = {
    name = "${local.project_name}_main_sg"
  }
}

# security group egress or outbound rules for ec2 instance!
resource "aws_vpc_security_group_egress_rule" "main" {
  description    = "make this open to everything from everywhere"
  security_group_id = aws_security_group.main.id
#  from_port     = 0
#  to_port       = 0
  ip_protocol    = "-1"  # this matches all protocols
  cidr_ipv4      = "0.0.0.0/0"
  tags = {
    name = "${local.project_name}_main_egress_rule"
  }
}

# security group ingress or inbound rules for public ec2 instance to allow ssh!
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  description    = "allow ssh from everywhere"
  security_group_id = aws_security_group.main.id
  from_port      = 22
  to_port        = 22
  ip_protocol    = "tcp"
  cidr_ipv4      = "0.0.0.0/0"
  tags = {
    name = "${local.project_name}_ssh_ingress_rule"
  }
}

# security group ingress rules for instances to allow http!
resource "aws_vpc_security_group_ingress_rule" "http" {
  description     = "allow http from everywhere"
  security_group_id = aws_security_group.main.id
  from_port      = 80
  to_port        = 80
  ip_protocol    = "tcp"
  cidr_ipv4      = "0.0.0.0/0"
  tags = {
    name = "${local.project_name}_http_ingress_rule"
  }
}


# get the most recent ami for Ubuntu 22.04
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-lunar-23.04-amd64-server-*"]
  }
}

# Get local ssh key pair file
resource "aws_key_pair" "local_key" {
  key_name   = local.ssh_key_name
  public_key = file("~/${local.ssh_key_name}.pem.pub")
}


# Create a separate module ec2 instances
module "ec2_instances" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  ami     = data.aws_ami.ubuntu.id
# instance_count   =  2

# for_each = toset(["instance_a", "instance_b"])
  for_each = {
    "web01"   = aws_subnet.main_a.id
    "web02"   = aws_subnet.main_b.id
  }
  name = "${each.key}"

  instance_type          = "t2.micro"
  key_name               = local.ssh_key_name
  monitoring             = true
  vpc_security_group_ids = [aws_security_group.main.id]
  subnet_id              = each.value

  tags = {
    Terraform   = "true"
    Environment = "dev"
    name        = "${local.project_name}_${each.key}"
    server_type = var.ec2_instances[each.key].server_type
  }
}

# Output public IP address for each instance
output "ec2_ips" {
  value = {
    for instance_key, instance_value in module.ec2_instances :
    # Create a map with instance name as key and public IP as value
    instance_key => instance_value.public_ip
  }
}

# Output public DNS name for each instance
output "ec2_dns" {
  value = {
    for instance_key, instance_value in module.ec2_instances :
    # Create a map with instance name as key and public DNS as value
    instance_key => instance_value.public_dns
  }
}

# Generate inventory for use Ansible
# Local varialbles to used to build Ansible inventory file
locals {
  prefix_length = length(local.project_name) + 1

  # Create a string for each server type that stores the server alias
  # and public dns for each server this will be when writing the inventory file

  web_servers = <<-EOT
  %{for instance_key, instance_value in module.ec2_instances}
    %{if var.ec2_instances[instance_key].server_type == "web"}
      ${instance_key}:
        ansible_host: ${instance_value.public_dns}
    %{endif}
  %{endfor}
  EOT
}

# Create Ansible Inventory file
# Specify the ssh key and user and the servers for each server type
resource "local_file" "inventory" {
  content = <<-EOF
  all:
    vars:
      ansible_ssh_private_key_file: "./${local.ssh_key_name}.pem"
      ansible_user: ubuntu
  web:
    hosts:
      ${local.web_servers}
  EOF

  filename = "./4640-assignment-app-files/hosts.yml"
}

# Generate Ansible configuration file
# Configure Ansible to use the inventory file created above and set ssh options
resource "local_file" "ansible_config" {
  content = <<-EOT
  [defaults]
  inventory = hosts.yml
  stdout_callback = debug
  private_key_file = "./demo_key.pem"

  [ssh_connection]
  host_key_checking = False
  ssh_common_args = -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null

  EOT

  filename = "./4640-assignment-app-files/ansible.cfg"

}
