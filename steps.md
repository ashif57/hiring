# Steps — Local & AWS Deployment

---

## Part 1 — Local Testing with Docker Compose

### Prerequisites
- Docker Desktop installed and running
- Git

### Step 1 — Clone and navigate
```bash
git clone <your-repo>
cd devops/quickstart
```

### Step 2 — Build all images
```bash
docker compose build
```
> First build takes ~10 minutes — the inference-worker downloads the gemma-3-270m model (~270MB) during build.

### Step 3 — Start everything
```bash
docker compose up
```

Watch the logs. You're waiting for these lines:
```
caller-worker     | Caller worker started - listening for calls
inference-worker  | Inference worker started - listening for calls
```
Both workers must appear before the API is ready.

### Step 4 — Test the API
```bash
curl -X POST http://localhost/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "user", "content": "What is 2 + 2?" }
    ]
  }'
```

Expected response:
```json
{
  "result": {
    "result": "2 + 2 equals 4.",
    "success": "You've connected two workers and they're interoperating seamlessly..."
  }
}
```

### Step 5 — Verify RPC chain is working
Check that the call went through all layers:
```bash
# See logs from all containers
docker compose logs -f

# Or per container
docker compose logs -f caller-worker
docker compose logs -f inference-worker
docker compose logs -f iii-engine
```

You should see in caller-worker logs:
```
inference::get_response called in TypeScript { messages: [...] }
Running http inference...
```

### Step 6 — Tear down
```bash
docker compose down
# To also remove the state store volume:
docker compose down -v
```

---

## Part 2 — AWS Deployment

### Prerequisites
- AWS account (free tier)
- AWS CLI installed and configured (`aws configure`)
- Terraform installed
- Your SSH key pair created in AWS EC2 console (or via CLI)
- Docker installed locally (to build and push images)

---

### Phase 1 — Push Docker Images to ECR

#### Step 1 — Create ECR repositories
```bash
aws ecr create-repository --repository-name iii-engine
aws ecr create-repository --repository-name caller-worker
aws ecr create-repository --repository-name inference-worker
aws ecr create-repository --repository-name gateway
```

#### Step 2 — Authenticate Docker to ECR
```bash
aws ecr get-login-password --region <your-region> | \
  docker login --username AWS --password-stdin \
  <your-account-id>.dkr.ecr.<your-region>.amazonaws.com
```

#### Step 3 — Build and push all images
```bash
# Set your ECR base URL
ECR=<your-account-id>.dkr.ecr.<your-region>.amazonaws.com

# iii-engine
docker build -t iii-engine ./engine
docker tag iii-engine:latest $ECR/iii-engine:latest
docker push $ECR/iii-engine:latest

# caller-worker
docker build -t caller-worker ./workers/caller-worker
docker tag caller-worker:latest $ECR/caller-worker:latest
docker push $ECR/caller-worker:latest

# inference-worker (slow — large image)
docker build -t inference-worker ./workers/inference-worker
docker tag inference-worker:latest $ECR/inference-worker:latest
docker push $ECR/inference-worker:latest

# gateway
docker build -t gateway ./gateway
docker tag gateway:latest $ECR/gateway:latest
docker push $ECR/gateway:latest
```

---

### Phase 2 — Provision Infrastructure with Terraform

#### Step 4 — Init and apply Terraform
```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Terraform creates:
- VPC `10.0.0.0/16`
- Public subnet `10.0.1.0/24` + Internet Gateway
- Private subnet `10.0.2.0/24` + NAT Gateway
- 3 EC2 instances (vm-gateway, vm-engine, vm-inference)
- Security groups (sg-gateway, sg-engine, sg-inference)
- Elastic IP on vm-gateway

Note the outputs:
```
gateway_public_ip  = "x.x.x.x"
vm_engine_private_ip = "10.0.2.10"
vm_inference_private_ip = "10.0.2.20"
```

---

### Phase 3 — Deploy on Each VM

#### Step 5 — SSH into vm-gateway (via public IP)
```bash
ssh -i ~/.ssh/<your-key>.pem ubuntu@<gateway_public_ip>
```

Pull and run the gateway container:
```bash
ECR=<your-account-id>.dkr.ecr.<your-region>.amazonaws.com

# Authenticate
aws ecr get-login-password --region <your-region> | \
  docker login --username AWS --password-stdin $ECR

# Pull and run
docker pull $ECR/gateway:latest
docker run -d \
  --name gateway \
  --restart unless-stopped \
  -p 80:80 \
  --add-host iii-engine:10.0.2.10 \
  $ECR/gateway:latest
```

> `--add-host iii-engine:10.0.2.10` makes the container resolve `iii-engine` to vm-engine's private IP.

---

#### Step 6 — SSH into vm-engine (via gateway as jump host)
```bash
ssh -i ~/.ssh/<your-key>.pem \
  -J ubuntu@<gateway_public_ip> \
  ubuntu@10.0.2.10
```

Pull and run iii-engine and caller-worker:
```bash
ECR=<your-account-id>.dkr.ecr.<your-region>.amazonaws.com

aws ecr get-login-password --region <your-region> | \
  docker login --username AWS --password-stdin $ECR

# Create a shared network so both containers can talk
docker network create iii-net

# Run iii-engine
docker pull $ECR/iii-engine:latest
docker run -d \
  --name iii-engine \
  --restart unless-stopped \
  --network iii-net \
  -p 3111:3111 \
  -p 49134:49134 \
  -v iii-data:/app/data \
  $ECR/iii-engine:latest

# Wait for engine to be ready
sleep 5

# Run caller-worker (connects to engine via Docker network)
docker pull $ECR/caller-worker:latest
docker run -d \
  --name caller-worker \
  --restart unless-stopped \
  --network iii-net \
  -e III_URL=ws://iii-engine:49134 \
  $ECR/caller-worker:latest
```

---

#### Step 7 — SSH into vm-inference (via gateway as jump host)
```bash
ssh -i ~/.ssh/<your-key>.pem \
  -J ubuntu@<gateway_public_ip> \
  ubuntu@10.0.2.20
```

Pull and run inference-worker:
```bash
ECR=<your-account-id>.dkr.ecr.<your-region>.amazonaws.com

aws ecr get-login-password --region <your-region> | \
  docker login --username AWS --password-stdin $ECR

docker pull $ECR/inference-worker:latest
docker run -d \
  --name inference-worker \
  --restart unless-stopped \
  -e III_URL=ws://10.0.2.10:49134 \
  $ECR/inference-worker:latest
```

> No `--network` needed here — the worker connects outbound to vm-engine's private IP directly over the subnet.

---

### Phase 4 — Test the AWS Deployment

#### Step 8 — Hit the public API
```bash
curl -X POST http://<gateway_public_ip>/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      { "role": "user", "content": "Explain what a VPC is in one sentence." }
    ]
  }'
```

Expected response:
```json
{
  "result": {
    "result": "A VPC (Virtual Private Cloud) is an isolated virtual network...",
    "success": "You've connected two workers and they're interoperating seamlessly..."
  }
}
```

#### Step 9 — Verify workers are connected (from vm-engine)
```bash
docker logs caller-worker
docker logs iii-engine
```

From vm-inference:
```bash
docker logs inference-worker
```

---

### Phase 5 — Verify Network Hygiene

#### Step 10 — Confirm private VMs are NOT reachable from internet
```bash
# These should all time out — no response from private VMs
curl --connect-timeout 5 http://<vm_engine_private_ip>:3111
curl --connect-timeout 5 http://<vm_inference_private_ip>:80

# Only this should work
curl http://<gateway_public_ip>/v1/chat/completions
```

---

### Tear Down AWS Resources
```bash
# Stop containers on each VM first, then:
cd terraform
terraform destroy
```

> Always destroy when done — NAT Gateway and EC2 instances incur hourly charges.
