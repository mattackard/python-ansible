output "master-url" {
  value = "http://${aws_instance.master.public_ip}"
}

output "worker-url1" {
  value = "http://${aws_instance.worker.0.public_ip}"
}

output "worker-url2" {
  value = "http://${aws_instance.worker.1.public_ip}"
}
