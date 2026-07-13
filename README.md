# Zero-Trust Spring Boot Hardening: Native K8s RBAC & AWS EKS IRSA

[![Kubernetes](https://img.shields.io/badge/kubernetes-v1.30+-blue.svg?logo=kubernetes&logoColor=white)](https://kubernetes.io)
[![Spring Boot](https://img.shields.io/badge/Spring%20Boot-3.2.4-brightgreen.svg?logo=springboot&logoColor=white)](https://spring.io/projects/spring-boot)
[![Java](https://img.shields.io/badge/Java-21-orange.svg?logo=openjdk&logoColor=white)](https://openjdk.org/projects/jdk/21/)
[![Security](https://img.shields.io/badge/DevSecOps-Hardened-red.svg)](https://en.wikipedia.org/wiki/DevSecOps)
[![Docker](https://img.shields.io/badge/Docker-Multi--Stage-2496ED.svg?logo=docker&logoColor=white)](https://www.docker.com/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

> **An enterprise-grade DevSecOps reference implementation** enforcing the *Principle of Least Privilege* on a containerized Spring Boot 3.x workload — from a hardened local `kind` cluster to a production-ready AWS EKS deployment via IRSA.

---

## 📋 Table of Contents

- [Architecture Overview](#-architecture-overview)
- [Security Controls](#-security-controls-implemented)
- [Repository Structure](#-repository-structure)
- [Local Deployment & Verification](#-local-deployment--verification)
- [Security Verification (Pentesting)](#-security-verification-simulating-attacks)
- [AWS EKS Migration with IRSA](#-production-ready-aws-eks-migration-irsa)
- [Author](#-author)

---

## 🏗️ Architecture Overview

This project demonstrates a **defense-in-depth** security posture applied at every layer of the container stack: from the Dockerfile runtime image to the Kubernetes control plane. The architecture transitions from a hardened local cluster (`kind`) to a secure, cloud-native deployment on AWS EKS.

```text
       [ Host Machine ]
              │ (Port 8080)
              ▼
    [ Kind Port Mapping ]
              │ (Port 30080 → NodePort)
              ▼
     [ Kubernetes Service ]  (secure-api-service:80)
              │
              ▼
   ┌──────────────────────────────────────────────────────────┐
   │  Namespace: secure-api-ns                                │
   │                                                          │
   │  ┌────────────────────────────────────────────────────┐  │
   │  │  Pod: secure-api-deployment                        │  │
   │  │  ├─ ServiceAccount: secure-api-sa                  │  │
   │  │  │    └─ RoleBinding ──► Role: secure-api-role     │  │
   │  │  │                                                 │  │
   │  │  ├─ Runtime Security (Container SecurityContext):  │  │
   │  │  │   ├─ runAsNonRoot: true  (UID/GID 1000)        │  │
   │  │  │   ├─ readOnlyRootFilesystem: true               │  │
   │  │  │   ├─ allowPrivilegeEscalation: false            │  │
   │  │  │   └─ capabilities.drop: [ALL]                   │  │
   │  │  │                                                 │  │
   │  │  └─ VolumeMounts:                                  │  │
   │  │      └─ /tmp  ◄── [ emptyDir Volume ]              │  │
   │  └────────────────────────────────────────────────────┘  │
   └──────────────────────────────────────────────────────────┘
```

---

## 🔒 Security Controls Implemented

Each control maps directly to a real-world attack vector with a concrete technical mitigation:

| Security Threat | Attack Scenario | Mitigation Strategy | Technical Control |
|---|---|---|---|
| **Root Execution** | Container breakout → kernel exploitation | Force non-root execution | `runAsNonRoot: true` + UID/GID `1000:1000` in Dockerfile & Pod `securityContext` |
| **Malicious Writes (RCE)** | Attacker injects a reverse shell via `/tmp` or OS dirs | Block filesystem writes | `readOnlyRootFilesystem: true` — only `/tmp` is writable via `emptyDir` |
| **Privilege Escalation** | Process spawns a child with elevated kernel capabilities | Drop all capabilities | `capabilities.drop: [ALL]` + `allowPrivilegeEscalation: false` |
| **Workload Over-Privilege** | Default `ServiceAccount` grants broad cluster access | Dedicated, scoped identity | Custom `secure-api-sa` bound to read-only `ConfigMaps` via namespace-scoped RBAC `Role` |
| **Lateral Movement** | Compromised pod enumerates secrets across namespaces | Scope RBAC & isolate namespace | `RoleBinding` scoped to `secure-api-ns`; no `ClusterRole` granted |
| **Static AWS Key Leak** | `AWS_ACCESS_KEY_ID` exposed in env vars or image layers | Eliminate static credentials | AWS EKS OIDC federation via **IRSA** — temporary STS tokens injected at runtime |

---

## 📁 Repository Structure

```
.
├── Dockerfile                  # Hardened multi-stage image: Maven builder + non-root JRE 21 runtime
├── pom.xml                     # Spring Boot 3.2.4 + Java 21 dependencies
├── kind-config.yaml            # Kind cluster config with host port 8080 → NodePort 30080 mapping
├── src/
│   └── main/java/.../
│       └── SecureApiApplication.java   # Spring Boot app + /api/v1/status health endpoint
└── k8s/                        # Kubernetes declarative manifests (apply in order)
    ├── namespace.yaml          # Isolation boundary: secure-api-ns
    ├── serviceaccount.yaml     # Dedicated workload identity (IRSA-annotated for EKS)
    ├── role.yaml               # Namespace-scoped Role: read-only access on ConfigMaps only
    ├── rolebinding.yaml        # Binds secure-api-sa to secure-api-role
    ├── deployment.yaml         # Pod spec with full SecurityContext hardening + resource limits
    └── service.yaml            # NodePort service exposing port 8080 locally
```

---

## 🚀 Local Deployment & Verification

### Prerequisites

Ensure the following tools are installed:

| Tool | Purpose | Install |
|---|---|---|
| [Docker Desktop](https://www.docker.com/products/docker-desktop/) | Build & run container images | [docs.docker.com](https://docs.docker.com/get-docker/) |
| [Kind](https://kind.sigs.k8s.io/) | Local multi-node K8s cluster | `brew install kind` |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | Kubernetes CLI | `brew install kubectl` |

### Step-by-Step Deployment

```bash
# 1. Build the hardened, non-root Docker image
docker build -t secure-api:1.0.0 .

# 2. Provision the Kind cluster with host port mapping (8080 → NodePort 30080)
kind create cluster --name secure-api-cluster --config kind-config.yaml

# 3. Load the local image into the Kind cluster node registry
kind load docker-image secure-api:1.0.0 --name secure-api-cluster

# 4. Create the namespace (isolation boundary)
kubectl apply -f k8s/namespace.yaml

# 5. Apply the complete RBAC profile (order matters)
kubectl apply -f k8s/serviceaccount.yaml
kubectl apply -f k8s/role.yaml
kubectl apply -f k8s/rolebinding.yaml

# 6. Deploy the workload and expose its service
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
```

### Verify the Deployment

Wait for the pod to reach `Running` state:

```bash
kubectl get pods -n secure-api-ns -w
```

```
NAME                                    READY   STATUS    RESTARTS   AGE
secure-api-deployment-xxxxxxxxx-xxxxx   1/1     Running   0          30s
```

Query the health endpoint from your host machine:

```bash
curl -i http://localhost:8080/api/v1/status
```

**Expected Response — HTTP 200 OK:**

```json
{
  "secured": true,
  "status": "UP",
  "message": "The Spring Boot API works perfectly",
  "timestamp": "2026-07-13T22:50:57.343815137Z"
}
```

---

## 🧪 Security Verification — Simulating Attacks

The following tests validate that every security control holds under real-world attack conditions. All commands simulate an attacker who has already achieved **remote code execution** inside the pod.

```bash
# Store the pod name for subsequent attack simulations
POD_NAME=$(kubectl get pods -n secure-api-ns -l app=secure-api -o jsonpath='{.items[0].metadata.name}')
```

---

### 🔴 Attack Vector 1 — RCE: Malicious Script Injection

**Scenario:** The attacker exploits an application vulnerability (e.g., deserialization, path traversal) and attempts to write a reverse shell or persistence script to the filesystem.

```bash
kubectl exec -it $POD_NAME -n secure-api-ns -- touch /tmp/malicious.sh
```

**Result: 🛡️ BLOCKED**

```
touch: /tmp/malicious.sh: Read-only file system
command terminated with exit code 1
```

> **Why:** `readOnlyRootFilesystem: true` mounts the container's root FS as read-only at the kernel level. The `/tmp` directory is accessible only for Tomcat's internal write needs via an in-memory `emptyDir` volume, but is not exposed to shell execution paths that would allow attacker persistence.

---

### 🔴 Attack Vector 2 — Token Theft & RBAC Privilege Escalation

**Scenario:** The attacker extracts the pod's ServiceAccount JWT and uses it against the Kubernetes API to enumerate Secrets (e.g., database credentials, TLS certificates).

```bash
# Step 1: Exfiltrate the active JWT from the mounted service account token
SA_TOKEN=$(kubectl exec -it $POD_NAME -n secure-api-ns -- \
  cat /var/run/secrets/kubernetes.io/serviceaccount/token)

# Step 2: Resolve the API server address
APISERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

# Step 3: Attempt to list Secrets using the stolen token
curl -k -H "Authorization: Bearer $SA_TOKEN" \
  $APISERVER/api/v1/namespaces/secure-api-ns/secrets
```

**Result: 🛡️ BLOCKED**

```json
{
  "status": "Failure",
  "message": "secrets is forbidden: User \"system:serviceaccount:secure-api-ns:secure-api-sa\" cannot list resource \"secrets\" in API group \"\" in the namespace \"secure-api-ns\"",
  "reason": "Forbidden",
  "code": 403
}
```

> **Why:** The Kubernetes control plane enforces RBAC at the API Gateway level. The custom `secure-api-role` grants **only** `get`, `list`, and `watch` on `configmaps` — Secrets, Pods, Deployments, and all other resources remain completely inaccessible to this identity, even from within the cluster.

---

## ☁️ Production-Ready AWS EKS Migration (IRSA)

To eliminate the risk of static credential exposure in production, this architecture uses **IAM Roles for Service Accounts (IRSA)** — federated identity between Kubernetes and AWS IAM via OIDC.

### How IRSA Works

```
Pod starts
  └─► EKS Mutating Admission Webhook detects IRSA annotation
        └─► Injects AWS_WEB_IDENTITY_TOKEN_FILE env var + projected volume
              └─► AWS SDK calls sts:AssumeRoleWithWebIdentity automatically
                    └─► Returns short-lived STS credentials (valid 1h)
                          └─► No static keys ever stored or exposed
```

### 1. ServiceAccount Annotation

```yaml
# k8s/serviceaccount.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: secure-api-sa
  namespace: secure-api-ns
  annotations:
    # Links the K8s identity to the AWS IAM Role via OIDC federation
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/secure-api-execution-role
automountServiceAccountToken: true
```

> The EKS Mutating Admission Webhook detects this annotation at pod startup and automatically mounts a short-lived STS Web Identity token into the pod — no manual credential management required.

### 2. AWS IAM Trust Policy

Configure the IAM Role to **only** trust your specific EKS OIDC Provider, scoped to this exact ServiceAccount and Namespace — preventing any other workload from assuming the role.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789012:oidc-provider/oidc.eks.eu-west-3.amazonaws.com/id/EXAMPLERANDOMID12345"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.eu-west-3.amazonaws.com/id/EXAMPLERANDOMID12345:aud": "sts.amazonaws.com",
          "oidc.eks.eu-west-3.amazonaws.com/id/EXAMPLERANDOMID12345:sub": "system:serviceaccount:secure-api-ns:secure-api-sa"
        }
      }
    }
  ]
}
```

**Key security properties of this trust policy:**
- `Federated` — restricts trust to your specific EKS cluster's OIDC issuer URL
- `aud` condition — ensures the token audience is exclusively AWS STS
- `sub` condition — pins access to a **single** ServiceAccount in a **single** Namespace; any other pod or account is denied

---

## 👨‍💻 Author

**Abdoul Aziz Dieng**  
*DevSecOps Engineer · Dakar, Senegal*

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Connect-0A66C2?logo=linkedin&logoColor=white)](https://www.linkedin.com/in/aadieng)
[![GitHub](https://img.shields.io/badge/GitHub-Follow-181717?logo=github&logoColor=white)](https://github.com/aadieng100)

---

<p align="center">
  <sub>Built with ☕ Java 21, 🐳 Docker, ☸️ Kubernetes & 🔐 Zero-Trust principles</sub>
</p>
