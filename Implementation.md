# Implementation Plan — Distributed Inference on AWS

---

## 1. Request Flow Architecture

```
Client (curl / browser)
        │
        │  POST /v1/chat/completions
        │  { "messages": [...] }
        ▼
┌─────────────────────────┐
│   vm-gateway            │
│   nginx :80             │
│   (Public Subnet)       │
└────────────┬────────────┘
             │  proxy_pass http://10.0.2.10:3111
             │  (over private subnet)
             ▼
┌─────────────────────────────────────────────────────┐
│   vm-engine  (10.0.2.10)                            │
│   Private Subnet                                    │
│                                                     │
│   ┌─────────────────────────────────────────────┐   │
│   │  iii engine (Rust binary)                   │   │
│   │  HTTP listener      :3111                   │   │
│   │  WebSocket broker   :49134                  │   │
│   └──────────┬──────────────────────────────────┘   │
│              │  (in-process RPC dispatch)            │
│   ┌──────────▼──────────────────────────────────┐   │
│   │  caller-worker (TypeScript / tsx)           │   │
│   │  registers: http::run_inference_over_http   │   │
│   │  registers: inference::get_response         │   │
│   │  connected via ws://localhost:49134         │   │
│   └──────────┬──────────────────────────────────┘   │
└──────────────┼──────────────────────────────────────┘
               │
               │  iii.trigger("inference::run_inference")
               │  WebSocket RPC  ws://10.0.2.10:49134
               │  (over private subnet)
               ▼
┌─────────────────────────────────────────────────────┐
│   vm-inference  (10.0.2.20)                         │
│   Private Subnet                                    │
│                                                     │
│   ┌─────────────────────────────────────────────┐   │
│   │  inference-worker (Python)                  │   │
│   │  registers: inference::run_inference        │   │
│   │  connected via ws://10.0.2.10:49134         │   │
│   │                                             │   │
│   │  loads: gemma-3-270m-Q8_0.gguf             │   │
│   │  via: HuggingFace transformers              │   │
│   └─────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
               │
               │  returns inference result (text)
               ▼
        (result bubbles back up the same chain)

caller-worker → iii engine → HTTP response → nginx → client
```

### Port Reference

| VM           | Port  | Protocol  | Purpose                          | Exposed to        |
|--------------|-------|-----------|----------------------------------|-------------------|
| vm-gateway   | 80    | HTTP      | nginx reverse proxy              | Internet (0.0.0.0/0) |
| vm-gateway   | 443   | HTTPS     | nginx TLS (optional)             | Internet (0.0.0.0/0) |
| vm-gateway   | 22    | SSH       | admin access                     | Your IP only      |
| vm-engine    | 3111  | HTTP      | iii HTTP API                     | Private subnet + sg-gateway |
| vm-engine    | 49134 | WebSocket | iii worker broker                | Private subnet only |
| vm-engine    | 22    | SSH       | admin (via bastion/gateway)      | sg-gateway only   |
| vm-inference | 22    | SSH       | admin (via bastion/gateway)      | sg-gateway only   |
| vm-inference | —     | —         | no inbound needed (outbound only)| —                 |

---

## 2. AWS Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│  AWS Region (e.g. ap-south-1)                                           │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  VPC  10.0.0.0/16                                                 │  │
│  │                                                                   │  │
│  │  ┌────────────────────────────────┐                               │  │
│  │  │  Public Subnet  10.0.1.0/24   │                               │  │
│  │  │                                │                               │  │
│  │  │  ┌──────────────────────────┐  │                               │  │
│  │  │  │  vm-gateway              │  │                               │  │
│  │  │  │  t2.micro                │  │                               │  │
│  │  │  │  Elastic IP (public)     │  │                               │  │
│  │  │  │  nginx :80               │  │                               │  │
│  │  │  │  sg-gateway              │  │                               │  │
│  │  │  └──────────────────────────┘  │                               │  │
│  │  │                                │                               │  │
│  │  │  Route Table:                  │                               │  │
│  │  │  0.0.0.0/0 → IGW              │                               │  │
│  │  └──────────────┬─────────────────┘                               │  │
│  │                 │                                                  │  │
│  │         Internet Gateway (IGW)                                    │  │
│  │                 │                                                  │  │
│  │  ┌──────────────▼─────────────────────────────────────────────┐   │  │
│  │  │  Private Subnet  10.0.2.0/24                               │   │  │
│  │  │                                                             │   │  │
│  │  │  ┌──────────────────────────┐  ┌────────────────────────┐  │   │  │
│  │  │  │  vm-engine               │  │  vm-inference          │  │   │  │
│  │  │  │  t2.micro                │  │  t2.medium             │  │   │  │
│  │  │  │  10.0.2.10 (private)     │  │  10.0.2.20 (private)   │  │   │  │
│  │  │  │                          │  │                        │  │   │  │
│  │  │  │  iii engine              │  │  inference-worker.py   │  │   │  │
│  │  │  │  :3111  (HTTP)           │◄─┤  III_URL=              │  │   │  │
│  │  │  │  :49134 (WebSocket)      │  │  ws://10.0.2.10:49134  │  │   │  │
│  │  │  │                          │  │                        │  │   │  │
│  │  │  │  caller-worker (TS)      │  │  gemma-3-270m GGUF     │  │   │  │
│  │  │  │  sg-engine               │  │  sg-inference          │  │   │  │
│  │  │  └──────────────────────────┘  └────────────────────────┘  │   │  │
│  │  │                                                             │   │  │
│  │  │  Route Table:                                               │   │  │
│  │  │  10.0.0.0/16 → local  (no IGW route = private)             │   │  │
│  │  └─────────────────────────────────────────────────────────────┘   │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

### Security Groups

**sg-gateway** (attached to vm-gateway)
```
Inbound:
  TCP 80    0.0.0.0/0        # HTTP from internet
  TCP 443   0.0.0.0/0        # HTTPS from internet (optional)
  TCP 22    <YOUR_IP>/32      # SSH from your IP only

Outbound:
  All traffic  0.0.0.0/0     # allow proxy to reach vm-engine
```

**sg-engine** (attached to vm-engine)
```
Inbound:
  TCP 3111   sg-gateway            # HTTP from nginx only
  TCP 49134  10.0.2.0/24          # WebSocket from private subnet (vm-inference)
  TCP 22     sg-gateway            # SSH via gateway

Outbound:
  All traffic  0.0.0.0/0
```

**sg-inference** (attached to vm-inference)
```
Inbound:
  TCP 22     sg-gateway            # SSH via gateway only
  (no other inbound — worker connects outbound to vm-engine)

Outbound:
  All traffic  0.0.0.0/0          # needs to reach vm-engine:49134
                                   # and internet for pip install / model download
```

---

## 3. IaC Plan (Terraform)

Files to create:
```
terraform/
├── main.tf          # provider, VPC, subnets, IGW, route tables
├── security.tf      # security groups
├── instances.tf     # EC2 instances
├── outputs.tf       # public IP of gateway, private IPs
└── variables.tf     # region, AMI, key pair name
```

---

## 4. Deployment Steps (per VM)

### vm-engine
```bash
# 1. Install iii engine
curl -fsSL https://install.iii.dev/iii/main/install.sh | sh

# 2. Clone repo, fix config.yaml (remove inference-worker entry, host: 0.0.0.0)
git clone <your-repo>
cd quickstart

# 3. Install caller-worker deps
cd workers/caller-worker && npm install && cd ../..

# 4. Start engine (runs caller-worker automatically)
iii start
```

### vm-inference
```bash
# 1. Install Python deps
pip install -r workers/inference-worker/requirements.txt

# 2. Point worker at vm-engine
export III_URL=ws://10.0.2.10:49134

# 3. Start worker
python workers/inference-worker/inference_worker.py
```

### vm-gateway
```bash
# nginx config
sudo apt install nginx -y
# write /etc/nginx/sites-available/iii with proxy_pass to 10.0.2.10:3111
sudo systemctl enable nginx && sudo systemctl start nginx
```

---

## 5. Test the API

```bash
curl -X POST http://<GATEWAY_PUBLIC_IP>/v1/chat/completions \
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
    "success": "You've connected two workers...",
    "result": "<model output text>"
  }
}
```
