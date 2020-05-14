resource "aws_key_pair" "demo_key" {
  key_name   = "terraform"
  public_key = file(var.public_key)
}

resource "aws_instance" "webserver" {
  count = var.instance_count

  ami           = var.ami
  instance_type = var.instance
  key_name      = aws_key_pair.demo_key.key_name

  vpc_security_group_ids = [
    aws_security_group.web.id,
    aws_security_group.ssh.id,
    aws_security_group.egress-tls.id,
    aws_security_group.ping-ICMP.id,
    aws_security_group.web_server.id
  ]


  ebs_block_device {
    device_name           = "/dev/sdg"
    volume_size           = 500
    volume_type           = "io1"
    iops                  = 2000
    encrypted             = true
    delete_on_termination = true
  }

  connection {
    host        = self.public_ip
    private_key = file(var.private_key)
    user        = var.ansible_user
  }

  # Ansible requires Python to be installed on the remote machine
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get update",
      "sudo apt-get -qq install python -y"
    ]
  }

  # Create ansible inventory and run playbook
  provisioner "local-exec" {
    command = <<EOT
      sleep 5;
      >webserver.ini;
      echo "[webserver]" | tee -a webserver.ini;
      echo "${aws_instance.webserver[count.index].public_ip} ansible_user=${var.ansible_user} ansible_ssh_private_key_file=${var.private_key}" | tee -a webserver.ini;
      export ANSIBLE_HOST_KEY_CHECKING=False;
      ansible-playbook -u ${var.ansible_user} --private-key ${var.private_key} -i webserver.ini ../playbooks/webserver.yaml
    EOT
  }

  tags = {
    Name     = "webserver-${count.index + 1}"
    Batch    = "7AM"
    Location = "California"
  }
}

resource "aws_security_group" "web" {
  name        = "default-web-example"
  description = "Security group for web that allows web traffic from internet"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "web-example-default-vpc"
  }
}

resource "aws_security_group" "ssh" {
  name        = "default-ssh-example"
  description = "Security group for nat instances that allows SSH and VPN traffic from internet"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ssh-example-default-vpc"
  }
}

resource "aws_security_group" "egress-tls" {
  name        = "default-egress-tls-example"
  description = "Default security group that allows inbound and outbound traffic from all instances in the VPC"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "egress-tls-example-default-vpc"
  }
}

resource "aws_security_group" "ping-ICMP" {
  name        = "default-ping-example"
  description = "Default security group that allows to ping the instance"

  ingress {
    from_port        = -1
    to_port          = -1
    protocol         = "icmp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "ping-ICMP-example-default-vpc"
  }
}

# Allow the web app to receive requests on port 8080
resource "aws_security_group" "web_server" {
  name        = "web_server"
  description = "Exposes port 5000 for flask webserver"

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "web_server-example-default-vpc"
  }
}
