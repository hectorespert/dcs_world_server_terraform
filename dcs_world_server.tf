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
  region = "us-west-2"
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

/*resource "aws_security_group" "winrm" {

  ingress {
    from_port = 5985
    to_port = 5985
    protocol = "tcp"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  ingress {
    from_port = 5985
    to_port = 5985
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
}*/

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
    //aws_security_group.winrm.name
  ]
  key_name = aws_key_pair.server_key.key_name
  get_password_data = "true"
  user_data = <<EOF
<powershell>
Initialize-Disk -Number 1 -PartitionStyle "GPT"
New-Partition -DiskNumber 1 -UseMaximumSize -AssignDriveLetter
Format-Volume -DriveLetter D -Confirm:$FALSE
</powershell>
EOF

  /*connection {
      type = "winrm"
      port = 5986
      host = self.public_dns
      user = "Administrator"
      password = rsadecrypt(self.password_data, tls_private_key.rsa_key.private_key_pem)
  }

  provisioner "remote-exec" {
    inline = [
      "echo Current date and time >> %SystemRoot%\\Temp\\test.log"
    ]
  }

  provisioner "file" {
    source = "test.txt"
    destination = "C:/test.txt"
  }*/

}

output "server-dns" {
  value = aws_instance.dcs_world_server.public_dns
}

output "password_data" {
  value = aws_instance.dcs_world_server.password_data
}

output "password_decrypted" {
  value = rsadecrypt(aws_instance.dcs_world_server.password_data, tls_private_key.rsa_key.private_key_pem)
}
