terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 2.70"
    }
  }
}

provider "aws" {
  profile = "default"
  region = "eu-west-1"
}

data "aws_ami" "amazon_windows_2019_std" {
  most_recent = true
  owners = [
    "amazon"
  ]

  filter {
    name = "name"
    values = [
      "Windows_Server-2019-English-Full-Base-*"
    ]
  }
}

resource "aws_security_group" "dcs_tcp" {

  ingress {
    from_port = 10308
    to_port = 10308
    protocol = "tcp"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  ingress {
    from_port = 10308
    to_port = 10308
    protocol = "tcp"
    ipv6_cidr_blocks = [
      "::/0"
    ]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    ipv6_cidr_blocks = [
      "::/0"
    ]
  }
}

resource "aws_security_group" "dcs_udp" {

  ingress {
    from_port = 10308
    to_port = 10308
    protocol = "udp"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  ingress {
    from_port = 10308
    to_port = 10308
    protocol = "udp"
    ipv6_cidr_blocks = [
      "::/0"
    ]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    ipv6_cidr_blocks = [
      "::/0"
    ]
  }
}

resource "aws_security_group" "srs_tcp" {

  ingress {
    from_port = 5002
    to_port = 5002
    protocol = "tcp"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  ingress {
    from_port = 5002
    to_port = 5002
    protocol = "tcp"
    ipv6_cidr_blocks = [
      "::/0"
    ]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    ipv6_cidr_blocks = [
      "::/0"
    ]
  }
}

resource "aws_security_group" "srs_udp" {

  ingress {
    from_port = 5002
    to_port = 5002
    protocol = "udp"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  ingress {
    from_port = 5002
    to_port = 5002
    protocol = "udp"
    ipv6_cidr_blocks = [
      "::/0"
    ]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    ipv6_cidr_blocks = [
      "::/0"
    ]
  }
}

resource "aws_security_group" "rdp" {

  ingress {
    from_port = 3389
    to_port = 3389
    protocol = "tcp"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  ingress {
    from_port = 3389
    to_port = 3389
    protocol = "tcp"
    ipv6_cidr_blocks = [
      "::/0"
    ]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    ipv6_cidr_blocks = [
      "::/0"
    ]
  }
}

resource "aws_security_group" "winrm" {

  ingress {
    from_port = 5986
    to_port = 5986
    protocol = "tcp"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  ingress {
    from_port = 5986
    to_port = 5986
    protocol = "tcp"
    ipv6_cidr_blocks = [
      "::/0"
    ]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    ipv6_cidr_blocks = [
      "::/0"
    ]
  }
}

resource "tls_private_key" "rsa_key" {
  algorithm = "RSA"
}

resource "aws_key_pair" "server_key" {
  public_key = tls_private_key.rsa_key.public_key_openssh
}

resource "aws_instance" "dcs_world_server" {
  ami = data.aws_ami.amazon_windows_2019_std.image_id
  instance_type = "c5ad.xlarge"
  security_groups = [
    aws_security_group.rdp.name,
    aws_security_group.winrm.name,
    aws_security_group.dcs_tcp.name,
    aws_security_group.dcs_udp.name,
	aws_security_group.srs_tcp.name,
    aws_security_group.srs_udp.name
  ]
  key_name = aws_key_pair.server_key.key_name
  get_password_data = "true"
  user_data = file("bootstrap_win.txt")

  connection {
      type = "winrm"
      port = 5986
      host = self.public_dns
      user = "Administrator"
      password = rsadecrypt(aws_instance.dcs_world_server.password_data, tls_private_key.rsa_key.private_key_pem)
      insecure = true
      https = true
      timeout = 15
  }

  /*
   * Check bootstrap
   */
  provisioner "remote-exec" {
    inline = [
      "PowerShell -Command \"Get-Content -Path C:\\ProgramData\\Amazon\\EC2-Windows\\Launch\\Log\\UserdataExecution.log\"",
	  "PowerShell -Command \"Get-Item Env:TEMP\"",
      "PowerShell -Command \"Get-Item Env:TMP\""
    ]
  }
  
  /*
   * Upload Server Configuration
   */
  provisioner "file" {
    source      = "ServerConfig\\Config"
    destination = "C:\\Users\\Administrator\\Saved Games\\DCS.openbeta_server\\Config"
  }
  
  /*
   * Upload Missions
   */
  provisioner "file" {
    source      = "ServerConfig\\Missions"
    destination = "C:\\Users\\Administrator\\Saved Games\\DCS.openbeta_server\\Missions"
  }

}

output "server-dns" {
  value = aws_instance.dcs_world_server.public_dns
}

output "password-decrypted" {
  value = rsadecrypt(aws_instance.dcs_world_server.password_data, tls_private_key.rsa_key.private_key_pem)
}
