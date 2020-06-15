resource "aws_key_pair" "terraform_key" {
  key_name   = "terraform"
  public_key = file(var.public_key)
}

resource "aws_instance" "master" {
  ami           = var.ami
  instance_type = var.master_instance
  key_name      = aws_key_pair.terraform_key.key_name

  vpc_security_group_ids = [
    aws_security_group.web.id,
    aws_security_group.ssh.id,
    aws_security_group.egress-default.id,
    aws_security_group.ping-ICMP.id,
    aws_security_group.kubeadm_master.id
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

  # Create ansible inventory for master and set python interpreter to use python3
  provisioner "local-exec" {
    command = <<EOT
      sleep 5;
      >inventory.ini;
      echo "[master]" | tee -a inventory.ini;
      echo "${aws_instance.master.public_ip} ansible_user=${var.ansible_user} ansible_ssh_private_key_file=${var.private_key}" | tee -a inventory.ini;
      echo "[all:vars]" | tee -a inventory.ini;
      echo "ansible_python_interpreter=/usr/bin/python3" | tee -a inventory.ini;
      export ANSIBLE_HOST_KEY_CHECKING=False
    EOT
  }

  tags = {
    Name     = "master"
    Batch    = "7AM"
    Location = "California"
  }
}

resource "aws_instance" "worker" {
  count = var.worker_instance_count

  ami           = var.ami
  instance_type = var.worker_instance
  key_name      = aws_key_pair.terraform_key.key_name

  vpc_security_group_ids = [
    aws_security_group.web.id,
    aws_security_group.ssh.id,
    aws_security_group.egress-default.id,
    aws_security_group.ping-ICMP.id,
    aws_security_group.kubeadm_worker.id
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
      "sudo apt-get -qq install python3 -y"
    ]
  }

  # Create ansible inventory for workers
  provisioner "local-exec" {
    command = <<EOT
      sleep 5;
      echo "[worker]" | tee -a inventory.ini;
      echo "${self.public_ip} ansible_user=${var.ansible_user} ansible_ssh_private_key_file=${var.private_key}" | tee -a inventory.ini;
      export ANSIBLE_HOST_KEY_CHECKING=False
    EOT
  }

  tags = {
    Name     = "worker-${count.index + 1}"
    Batch    = "7AM"
    Location = "California"
  }
}

# null resource is used to only run the playbook once per group of instances
resource "null_resource" "ansible-all" {
  depends_on = [aws_instance.master, aws_instance.worker]
  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -u ${var.ansible_user} --private-key ${var.private_key} -i inventory.ini ../playbooks/install_kubernetes.yaml"
  }
}

# runs the ansible playbook specific to the master node
resource "null_resource" "ansible-master" {
  depends_on = [null_resource.ansible-all]
  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -u ${var.ansible_user} --private-key ${var.private_key} -i inventory.ini ../playbooks/master_node.yaml"
  }
}

# runs the ansible playbook specific to the group of worker nodes
resource "null_resource" "ansible-worker" {
  depends_on = [null_resource.ansible-master]
  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -u ${var.ansible_user} --private-key ${var.private_key} -i inventory.ini ../playbooks/worker_node.yaml"
  }
}

resource "aws_security_group" "web" {
  name        = "http-https"
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
    Name = "http-https"
  }
}

resource "aws_security_group" "ssh" {
  name        = "ssh"
  description = "Security group for nat instances that allows SSH and VPN traffic from internet"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ssh"
  }
}

resource "aws_security_group" "egress-default" {
  name        = "default-egress"
  description = "Default security group that allows inbound and outbound traffic from all instances in the VPC"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "egress-default"
  }
}

resource "aws_security_group" "ping-ICMP" {
  name        = "default-ping"
  description = "Default security group that allows to ping the instance"

  ingress {
    from_port        = -1
    to_port          = -1
    protocol         = "icmp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "ping-default"
  }
}

# Kubeadm master node network ports
resource "aws_security_group" "kubeadm_master" {
  name        = "kubeadm_master"
  description = "Exposes ports for the kubeadm master node"

  # api server
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # etcd server
  ingress {
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # kubelet api, kube-scheduler, kube-controller-manager
  ingress {
    from_port   = 10250
    to_port     = 10252
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "kubeadm_master"
  }
}

# Kubeadm worker node network ports
resource "aws_security_group" "kubeadm_worker" {
  name        = "kubeadm_worker"
  description = "Exposes ports for a kubeadm worker node"

  # default nodeport range
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # kubelet api
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "kubeadm_worker"
  }
}

# Allow the web app to receive requests on port 8080
resource "aws_security_group" "flask_server" {
  name        = "flask_server"
  description = "Exposes port 5000 for flask webserver"

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "flask_server"
  }
}
