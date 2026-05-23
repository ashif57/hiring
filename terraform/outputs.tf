# ──────────────────────────────────────────────────────────────────────────────
# outputs.tf — Values printed after terraform apply
# Use these to SSH into VMs and configure your deployment scripts
# ──────────────────────────────────────────────────────────────────────────────

output "gateway_public_ip" {
  description = "Public IP of vm-gateway — use this in curl commands and DNS"
  value       = aws_eip.gateway.public_ip
}

output "engine_private_ip" {
  description = "Private IP of vm-engine — set as III_URL host on vm-inference"
  value       = aws_instance.engine.private_ip
}

output "inference_private_ip" {
  description = "Private IP of vm-inference"
  value       = aws_instance.inference.private_ip
}

output "ssh_gateway" {
  description = "SSH command to connect to vm-gateway"
  value       = "ssh -i ~/.ssh/<your-key>.pem ubuntu@${aws_eip.gateway.public_ip}"
}

output "ssh_engine" {
  description = "SSH command to connect to vm-engine via gateway jump host"
  value       = "ssh -i ~/.ssh/<your-key>.pem -J ubuntu@${aws_eip.gateway.public_ip} ubuntu@${aws_instance.engine.private_ip}"
}

output "ssh_inference" {
  description = "SSH command to connect to vm-inference via gateway jump host"
  value       = "ssh -i ~/.ssh/<your-key>.pem -J ubuntu@${aws_eip.gateway.public_ip} ubuntu@${aws_instance.inference.private_ip}"
}

output "api_endpoint" {
  description = "The public HTTP endpoint to call for inference"
  value       = "http://${aws_eip.gateway.public_ip}/v1/chat/completions"
}

output "curl_test_command" {
  description = "Ready-to-run curl command to test the API"
  value       = <<-EOT
    curl -X POST http://${aws_eip.gateway.public_ip}/v1/chat/completions \
      -H "Content-Type: application/json" \
      -d '{"messages": [{"role": "user", "content": "What is 2 + 2?"}]}'
  EOT
}
