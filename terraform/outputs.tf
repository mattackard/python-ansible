output "server-url" {
  value = "http://${aws_instance.webserver.0.public_ip}"
}
