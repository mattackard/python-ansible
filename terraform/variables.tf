variable "profile" {
  default = "terraform"
}

variable "region" {
  default = "us-west-1"
}

variable "instance" {
  default = "t2.nano"
}

variable "instance_count" {
  default = "1"
}

variable "public_key" {
  default = "~/.ssh/aws_terraform_key.pub"
}

variable "private_key" {
  default = "~/.ssh/aws_terraform_key.pem"
}

variable "ansible_user" {
  default = "ubuntu"
}

variable "ami" {
  default = "ami-0f56279347d2fa43e" # ubuntu 18.04 us-west-1

}
