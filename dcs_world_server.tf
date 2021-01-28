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
  instance_type = "c5ad.large" //c5ad.xlarge
  security_groups = [
    aws_security_group.rdp.name,
    aws_security_group.winrm.name
  ]
  key_name = aws_key_pair.server_key.key_name
  get_password_data = "true"
  user_data = <<EOF
<powershell>
write-output "Running User Data Script"
write-host "(host) Running User Data Script"

Set-ExecutionPolicy Unrestricted -Scope LocalMachine -Force -ErrorAction Ignore

# Don't set this before Set-ExecutionPolicy as it throws an error
$ErrorActionPreference = "stop"

# Remove HTTP listener
Remove-Item -Path WSMan:\Localhost\listener\listener* -Recurse

# Create a self-signed certificate to let ssl work
$Cert = New-SelfSignedCertificate -CertstoreLocation Cert:\LocalMachine\My -DnsName "packer"
New-Item -Path WSMan:\LocalHost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $Cert.Thumbprint -Force

# WinRM
write-output "Setting up WinRM"
write-host "(host) setting up WinRM"

cmd.exe /c winrm quickconfig -q
cmd.exe /c winrm set "winrm/config" '@{MaxTimeoutms="1800000"}'
cmd.exe /c winrm set "winrm/config/winrs" '@{MaxMemoryPerShellMB="1024"}'
cmd.exe /c winrm set "winrm/config/service" '@{AllowUnencrypted="true"}'
cmd.exe /c winrm set "winrm/config/client" '@{AllowUnencrypted="true"}'
cmd.exe /c winrm set "winrm/config/service/auth" '@{Basic="true"}'
cmd.exe /c winrm set "winrm/config/client/auth" '@{Basic="true"}'
cmd.exe /c winrm set "winrm/config/service/auth" '@{CredSSP="true"}'
cmd.exe /c winrm set "winrm/config/listener?Address=*+Transport=HTTPS" "@{Port=`"5986`";Hostname=`"packer`";CertificateThumbprint=`"$($Cert.Thumbprint)`"}"
cmd.exe /c netsh advfirewall firewall set rule group="remote administration" new enable=yes
cmd.exe /c netsh firewall add portopening TCP 5986 "Port 5986"
cmd.exe /c net stop winrm
cmd.exe /c sc config winrm start= auto
cmd.exe /c net start winrm

# Disable windows defender
Set-MpPreference -DisableRealtimeMonitoring $TRUE

# Init instance disk
Initialize-Disk -Number 1 -PartitionStyle "GPT"
New-Partition -DiskNumber 1 -UseMaximumSize -AssignDriveLetter
Format-Volume -DriveLetter D -Confirm:$FALSE

# Change Administrator Temporal folder
$oldTemp = [System.Environment]::GetEnvironmentVariable('TEMP', 'USER')
Write-Output "Old TEMP folder: " $oldTemp

Copy-Item -Verbose -Path $oldTemp -Destination D:\Temp -recurse -Force
[System.Environment]::SetEnvironmentVariable('TEMP', 'D:\Temp', 'USER')
[System.Environment]::SetEnvironmentVariable('TMP', 'D:\Temp', 'USER')

</powershell>
EOF

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

  provisioner "remote-exec" {
    inline = [
      "PowerShell -Command \"Get-Content -Path C:\\ProgramData\\Amazon\\EC2-Windows\\Launch\\Log\\UserdataExecution.log\"",
      "PowerShell -Command \"Get-Item Env:TEMP\"",
      "PowerShell -Command \"Get-Item Env:TMP\""
    ]
  }

  /*provisioner "file" {
    source      = "dcs_server_install_script.ps1"
    destination = "D:/dcs_server_install_script.ps1"
  }

  provisioner "remote-exec" {
    inline = [
      "PowerShell -ExecutionPolicy Bypass D:\\dcs_server_install_script.ps1 -drive D:"
    ]
  }*/

}

output "server-dns" {
  value = aws_instance.dcs_world_server.public_dns
}

output "password_decrypted" {
  value = rsadecrypt(aws_instance.dcs_world_server.password_data, tls_private_key.rsa_key.private_key_pem)
}
