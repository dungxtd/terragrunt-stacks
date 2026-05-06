# Cluster Lifecycle — Step by Step

Audience: anyone (no prior infra/k8s knowledge required).

This explains exactly what happens when you run `make stack-vault-production apply` or `destroy` — what each piece is, why it exists, and what depends on what.

---

## Glossary (read first)

| Term | Plain meaning |
|---|---|
| **AWS** | Cloud provider where everything runs |
| **VPC** | A private network inside AWS — isolates this project from others |
| **Subnet** | A slice of the VPC. Pods live in private subnets; load balancers in public subnets |
| **EKS** | Managed Kubernetes from AWS. The "computer cluster" that runs containers |
| **Pod** | One running container (or small group) inside Kubernetes |
| **Helm** | Package manager for Kubernetes. Like `apt-get install` but for k8s apps |
| **IAM role** | An AWS identity that grants permissions to do things in AWS |
| **IRSA** | "IAM Roles for Service Accounts" — lets a pod assume an AWS IAM role without API keys |
| **KMS** | AWS Key Management Service — provides encryption keys |
| **RDS** | Managed PostgreSQL database from AWS |
| **Vault** | Secret manager. Stores DB passwords, API keys, TLS certs. Apps fetch secrets at runtime instead of hard-coding them |
| **Vault unseal** | Vault encrypts itself at rest. To start, it needs a key to "unseal." We use AWS KMS to provide that key automatically |
| **Linkerd** | A "service mesh." It transparently adds mTLS encryption + retries + metrics between pods, with no code change in apps |
| **ArgoCD** | GitOps controller. Watches a Git repo and keeps Kubernetes synced with what's in Git |
| **ALB** | Application Load Balancer (AWS) — the public HTTPS endpoint that routes traffic to pods |
| **Target Group** | List of pod IPs the ALB sends traffic to |
| **TargetGroupBinding** | A Kubernetes resource that tells the ALB controller "register pods of service X to target group Y" |
| **SSM Parameter Store** | AWS's encrypted key/value store. We use it to remember the Vault root token between machines |
| **Terraform / Terragrunt** | The tools that build all this infrastructure declaratively from the `units/` and `stacks/` folders |

---

## Apply (create cluster) — full flow

```mermaid
flowchart TB
    Start([make stack-vault-production apply]) --> L1

    subgraph L1 [Layer 1: Network]
        VPC[VPC + subnets + NAT gateway<br/><i>private network in AWS</i>]
    end

    subgraph L2 [Layer 2: Compute]
        EKS[EKS cluster + node group<br/><i>4 t3.small EC2 instances run pods</i>]
    end

    subgraph L3 [Layer 3: Encryption keys]
        KMS[KMS keys<br/><i>encrypt Vault, SOPS, TF state</i>]
    end

    subgraph L4 [Layer 4: Data + Vault install]
        RDS[RDS PostgreSQL<br/><i>app database</i>]
        IRSA[Vault IAM role<br/><i>lets Vault pod talk to KMS</i>]
        VLT[Vault Helm install<br/><i>3 pods, sealed, not yet usable</i>]
        SSMPlaceholder[SSM parameters created<br/><i>placeholder values</i>]
        VaultInit[scripts/vault-init.sh<br/><i>operator init → real token + 5 keys</i>]
        SSMReal[SSM parameters overwritten<br/><i>now hold real secrets</i>]

        IRSA --> VLT
        VLT --> SSMPlaceholder
        SSMPlaceholder --> VaultInit
        VaultInit --> SSMReal
    end

    subgraph L5 [Layer 5: Vault config + TLS certs]
        Certs[Vault PKI mounts<br/><i>internal CA for service certs</i>]
        VCfg[Vault secrets engines<br/><i>DB dynamic credentials, policies</i>]
    end

    subgraph L6 [Layer 6: Platform on cluster]
        ALBCtrl[aws-alb-controller<br/><i>watches k8s, registers pods to ALB</i>]
        Lnk[Linkerd<br/><i>installs mTLS sidecars across cluster</i>]
        Argo[ArgoCD<br/><i>GitOps engine, watches this repo</i>]
        ALBTF[ALB unit<br/><i>TF creates ALB + TargetGroup + listener</i>]
        TGB[TargetGroupBinding CR<br/><i>tells controller: register frontend pods to TG</i>]

        ALBCtrl --> Lnk
        ALBCtrl --> Argo
        ALBCtrl --> ALBTF
        ALBTF --> TGB
    end

    subgraph L7 [Layer 7: CI Runner]
        GHR[GitHub Actions self-hosted runner<br/><i>runs CI jobs inside the cluster</i>]
    end

    subgraph Async [Async: ArgoCD syncs apps from Git]
        ESec[external-secrets<br/><i>fetches values from Vault into k8s Secrets</i>]
        SStores[secret-stores config]
        DD[Datadog agent<br/><i>metrics/logs to Datadog</i>]
        Flag[Flagger + loadtester<br/><i>canary deployment controller</i>]
        PaymentsApp[payments-app<br/><i>frontend + API + processor pods</i>]

        ESec --> SStores --> DD --> Flag --> PaymentsApp
    end

    Start --> L1 --> L2 --> L3 --> L4 --> L5 --> L6 --> L7
    L7 -->|kubectl apply gitops/apps/root.yaml| Async
    Async -->|frontend pod ready| TGB
    TGB -->|controller registers pod IP| ALBPublic[(ALB public DNS<br/>traffic flowing)]

    style Start fill:#dff
    style ALBPublic fill:#dfd
    style VaultInit fill:#fed
    style SSMReal fill:#fed
```

### Step-by-step narration

#### Step 1 — VPC (private network)

**What:** Carves out an isolated network in AWS (`10.0.0.0/16`).
- Public subnets: where the load balancer lives (reachable from internet)
- Private subnets: where pods + database live (NOT reachable from internet)
- NAT gateway: lets private pods reach the internet for image pulls etc., but not vice-versa

**Why first:** everything else needs a network to live in.

#### Step 2 — EKS (Kubernetes cluster)

**What:** AWS-managed Kubernetes control plane + 4 worker EC2 nodes (`t3.small`).
- Control plane = the "brain" — schedules pods, tracks state
- Nodes = the actual servers running container workloads
- Add-ons installed: VPC-CNI, kube-proxy, CoreDNS, EBS-CSI driver

**Why second:** all later layers run as pods inside this cluster.

#### Step 3 — KMS (encryption keys)

**What:** Three customer-managed encryption keys:
- Vault auto-unseal key (used in step 4 to unlock Vault)
- SOPS key (encrypt secrets in Git)
- Terraform state encryption key

**Why before Vault:** Vault references the unseal key.

#### Step 4 — Data + Vault install

This layer has 5 sub-steps that run in dependency order:

##### 4a. RDS PostgreSQL
A managed Postgres database (`db.t3.micro`). Multi-AZ disabled. Used by the payments app.

##### 4b. Vault IAM role (vault-irsa)
Creates an IAM role + IRSA mapping so the Vault pod can call `kms:Decrypt` on the unseal key from step 3.

##### 4c. Helm install Vault (HA mode)
Helm chart deploys 3 Vault pods (`vault-0`, `vault-1`, `vault-2`) configured with raft storage and AWS KMS auto-unseal. Pods start **sealed** — they can't yet store/serve secrets.

##### 4d. SSM parameter placeholders
Six AWS SSM parameters created (`/terragrunt-infra/vault/root-token` + 5 recovery keys), all containing `"placeholder"`. These are tracked in Terraform state — important for clean destroy later.

##### 4e. `scripts/vault-init.sh` runs (terragrunt after-hook)
- Waits until `vault-0` pod is `Running`
- Calls `vault operator init -recovery-shares=5 -recovery-threshold=3`
- Vault returns: `{ root_token, recovery_keys[5] }` (one-time event!)
- Writes those values to the SSM parameters from step 4d (`--overwrite`)
- Idempotent: if Vault already initialized, exits 0 without doing anything

After this, Vault is unsealed and operational.

#### Step 5 — Vault config + certs

##### 5a. Certs unit
Creates Vault PKI engine mounts — Vault becomes an internal Certificate Authority. Used for issuing TLS certs to internal services.

##### 5b. Vault config unit
Configures Vault:
- Database secrets engine (Vault generates short-lived DB credentials on demand)
- Auth methods (Kubernetes service account → Vault role)
- Policies (which apps can read which secrets)

#### Step 6 — Platform on cluster

##### 6a. aws-alb-controller
Helm install of the [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/) — a pod that watches Kubernetes for `Ingress` and `TargetGroupBinding` resources and reflects them as AWS ALB / Target Group state.

It needs to install **before** Linkerd and ArgoCD because both deploy Services that may need it. (We don't actually create Ingresses anymore — see step 6d.)

##### 6b. Linkerd
Helm install. Installs:
- `linkerd-crds` — custom resource types
- `linkerd-control-plane` — pods: `linkerd-destination`, `linkerd-identity`, `linkerd-proxy-injector` (in `linkerd` namespace)
- `linkerd-viz` — observability dashboard pods

What Linkerd does at runtime: when a pod is annotated `linkerd.io/inject: enabled`, the proxy injector adds a tiny sidecar container to it. The sidecar transparently encrypts all traffic (mTLS), retries failed requests, and emits golden metrics.

##### 6c. ArgoCD
Helm install. Pods include `argocd-server`, `argocd-application-controller`, `argocd-repo-server`. Once running, ArgoCD watches the `gitops/apps/` folder of this repo and creates Kubernetes resources matching what's in Git.

##### 6d. ALB unit (TF-managed)
- Creates an AWS ALB + Target Group + Listener via Terraform
- Creates a `TargetGroupBinding` Kubernetes resource (CRD from aws-alb-controller)
- The TGB tells the controller: "register pods of service `frontend` in namespace `payments-app` to this Target Group"
- Because the ALB lives in TF state, `terraform destroy` deletes it cleanly. No leak.

#### Step 7 — GitHub runner

Helm install of `actions-runner-controller` + a runner scale set. Lets GitHub Actions jobs run inside the cluster (private VPC access) instead of GitHub-hosted runners.

#### Async — ArgoCD syncs apps from Git

Once the cluster is up, you (or CI) run:
```bash
make gitops-bootstrap   # kubectl apply -f gitops/apps/root.yaml
```

This creates one ArgoCD Application named `root`, which watches `gitops/apps/` recursively. Children apps deploy in **sync wave** order:

| Wave | App | What |
|---|---|---|
| 0 | external-secrets | Helm operator that fetches secrets from Vault → creates k8s Secret objects |
| 1 | secret-stores | Configures `SecretStore` CRs that point external-secrets at Vault |
| 2 | datadog | Installs the Datadog agent (logs/metrics) |
| 3 | flagger / loadtester | Canary deployment controller + traffic generator |
| 4 | payments-app | The actual app: frontend, API, processor, product DB |

When the `payments-app` `frontend` pod becomes Ready, the aws-alb-controller (running since step 6a) sees it via the TargetGroupBinding from step 6d and registers its IP into the AWS Target Group. Now the ALB's public DNS serves real traffic.

---

## Destroy — short flow

```mermaid
flowchart TB
    Start([make stack-vault-production destroy]) --> Cascade

    subgraph Cascade [Phase 1: ArgoCD cascade]
        A1[argocd app delete root --cascade=foreground]
        A2[Finalizers tear down apps in reverse wave order]
        A3[k8s deletes Ingress, PVC, Service-LB resources]
        A4[Controllers reconcile: ALB pods deregister, EBS volumes deleted]
        A1 --> A2 --> A3 --> A4
    end

    subgraph TFDestroy [Phase 2: Terraform destroy]
        T1[Layer 6 reverse: alb → argocd → linkerd → aws-alb]
        T2[Layer 5: vault-config → certs]
        T3[Layer 4: vault → SSM parameters native delete<br/>+ vault-irsa, rds]
        T4[Layer 3: kms keys scheduled for deletion 7 days]
        T5[Layer 2: EKS torn down]
        T6[Layer 1: VPC deleted]
        T1 --> T2 --> T3 --> T4 --> T5 --> T6
    end

    Start --> Cascade --> TFDestroy --> Done([✓ Zero AWS resources remaining])

    style Start fill:#dff
    style Done fill:#dfd
    style Cascade fill:#fed
```

### Why this destroy is leak-free

| Concern | How handled |
|---|---|
| **k8s LoadBalancer / Ingress orphans ALB** | ArgoCD cascade deletes apps → Ingress → ALB controller cleans LB |
| **PVC orphans EBS volumes** | `kubectl delete pvc` triggers ebs-csi to delete volumes (`reclaimPolicy: Delete`) |
| **SSM parameters orphan** | Tracked as `aws_ssm_parameter` resources → TF destroy calls AWS DeleteParameter |
| **ALB itself** | TF-managed in `units/alb` → TF destroy calls AWS DeleteLoadBalancer |
| **KMS keys pile up** | `deletion_window_in_days = 7` (was 10 / 30) — minimal lingering |

If any phase fails, the workflow halts loud. No silent `|| true` paths.

---

## Mental model summary

```mermaid
flowchart LR
    subgraph Foundation
        N[Network: VPC]
        C[Compute: EKS]
        K[Crypto: KMS]
    end

    subgraph Data
        D[(RDS Postgres)]
        V[Vault HA]
        S[(SSM secrets)]
    end

    subgraph Mesh & GitOps
        L[Linkerd<br/>mTLS sidecars]
        A[ArgoCD<br/>GitOps]
    end

    subgraph Edge
        ALB[ALB + TG<br/>public entry]
    end

    subgraph Apps
        App[payments-app pods<br/>frontend/api/processor]
    end

    N --> C
    C --> V & D & L & A & ALB & App
    K --> V
    V --> S
    A --> App
    L --> App
    ALB --> App
```

- **Foundation** is built once by Terraform, slow-changing
- **Data** holds state (DB rows, secrets)
- **Mesh & GitOps** are infrastructure for safer/easier app delivery
- **Edge** is how the world reaches your app
- **Apps** are what users actually use

Everything below `Apps` exists to make `Apps` reliable, secure, and observable.

---

## Runtime — what happens when a user makes a request

Cluster is up. User opens browser, hits the ALB DNS. This section traces a single HTTP request through every component.

### Request lifecycle

```mermaid
sequenceDiagram
    autonumber
    actor U as User browser
    participant DNS as Public DNS
    participant ALB as AWS ALB
    participant TG as Target Group
    participant FE as frontend pod<br/>(+ Linkerd sidecar)
    participant PAPI as public-api pod<br/>(+ Linkerd sidecar)
    participant APP as payments-app pod<br/>(+ Linkerd sidecar)
    participant VLT as Vault
    participant DB as RDS Postgres
    participant DD as Datadog agent
    participant LV as Linkerd-viz

    U->>DNS: GET hashicups.example.com
    DNS-->>U: A record → ALB DNS
    U->>ALB: HTTP/HTTPS request
    ALB->>TG: Pick healthy target (round-robin)
    TG->>FE: Forward to pod IP:80
    Note over FE: Linkerd sidecar accepts<br/>plaintext from ALB,<br/>terminates inbound proxy
    FE->>PAPI: HTTP /api → public-api:8080<br/>(plaintext from app code)
    Note over FE,PAPI: Linkerd sidecars upgrade<br/>connection to mTLS automatically
    PAPI->>APP: HTTP → payments-app:8080
    Note over APP: First request:<br/>vault-agent sidecar fetches<br/>DB creds from Vault

    APP->>VLT: AppRole/SA login
    VLT-->>APP: Vault token
    APP->>VLT: GET database/creds/payments
    Note over VLT,DB: Vault generates new DB user<br/>with TTL=1h (dynamic creds)
    VLT->>DB: CREATE USER + GRANT
    VLT-->>APP: { username, password, lease_id }
    APP->>DB: SELECT ... (using Vault-issued creds)
    DB-->>APP: rows
    APP-->>PAPI: JSON response
    PAPI-->>FE: JSON response
    FE-->>ALB: HTTP 200 + HTML/JSON
    ALB-->>U: HTTP 200

    par Observability (continuous, async)
        FE->>DD: stdout logs → Datadog agent (DaemonSet)
        APP->>DD: stdout logs
        FE->>LV: Linkerd proxy metrics<br/>(success rate, p99 latency)
    end
```

### Step-by-step narration

#### 1-3. DNS and ALB

User's browser does a DNS lookup for the app's hostname (in a real setup you'd put a CNAME pointing to the ALB DNS — for demo, you can hit the ALB DNS directly).

The ALB lives in public subnets and has a security group allowing port 80 from `0.0.0.0/0`.

#### 4. Target Group selects pod

The ALB's HTTP listener forwards to a Target Group. The Target Group has a list of pod IPs (registered by `aws-alb-controller` because of the `TargetGroupBinding` we declared in the `alb` Terraform unit).

Health checks on the TG (`GET /` expects 200-399) ensure only Ready pods get traffic.

#### 5-6. Pod receives, Linkerd handles

Each pod has 2 containers running:
- The actual app container (`frontend`)
- A Linkerd `proxy` sidecar (auto-injected because the namespace has `linkerd.io/inject=enabled`)

The sidecar transparently:
- Terminates incoming connections
- Upgrades pod-to-pod traffic to mTLS (without app code knowing)
- Records latency, success rate, traffic volume

#### 7-8. Internal mTLS hops

`frontend` → `public-api` → `payments-app`. Each hop:
- App code makes a plain HTTP call to `<service>:<port>`
- Local Linkerd sidecar intercepts, encrypts, sends to remote sidecar
- Remote sidecar decrypts, hands plaintext to remote app

App developer sees plaintext. Network sees mTLS only.

#### 9-13. Vault dynamic database credentials

When `payments-app` needs to query the database:

1. The pod has a **vault-agent sidecar** (separate from Linkerd's sidecar — it's a Helm-chart-injected init/sidecar that handles secret retrieval).
2. Vault-agent authenticates to Vault using the pod's Kubernetes ServiceAccount token (Kubernetes auth method).
3. Vault-agent calls `database/creds/payments`. Vault, using its DB secrets engine, runs `CREATE USER + GRANT` on RDS, returns a fresh username/password with a 1-hour lease.
4. Vault-agent writes the creds to a file inside the pod (`/vault/secrets/database.properties`).
5. App reads the file and connects to RDS.

When the lease expires, Vault revokes the user automatically. **No long-lived password ever exists in the app's memory or environment.**

#### 14-16. Database and response

The app queries RDS using the short-lived creds, gets results, returns up the chain.

#### 17-18. Response back to user

`payments-app` → `public-api` → `frontend` → ALB → user. All inter-pod hops are mTLS via Linkerd.

#### Async — Observability

While the request flows, two things happen continuously:

- **Datadog agent (DaemonSet on every node)** scrapes pod stdout/stderr, OS metrics, k8s events. Sends to Datadog SaaS.
- **Linkerd proxies** emit golden metrics (success rate, requests/sec, p50/p95/p99 latency) which `linkerd-viz` aggregates. View them with `linkerd viz dashboard`.

### What each component contributes

```mermaid
flowchart LR
    Req([HTTP request]) --> ALB
    ALB -->|"routing<br/>+ TLS termination"| FE[frontend]
    FE -->|"mTLS<br/>(Linkerd)"| API[backend services]
    API -->|"dynamic DB creds<br/>(Vault)"| DB[(Postgres)]

    Vault[Vault] -.issues short-lived creds.-> API
    Linkerd[Linkerd sidecars] -.encrypts pod-to-pod.-> API
    Linkerd -.encrypts.-> FE
    Datadog[Datadog agent] -.collects logs/metrics.-> FE
    Datadog -.collects.-> API

    style Req fill:#dff
    style DB fill:#fed
    style Vault fill:#fed
```

| Component | Job at request time |
|---|---|
| **ALB** | Public entry point. Decides which pod gets the request based on TG health checks. |
| **aws-alb-controller** | Idle at request time. Only acts when pods come and go (registers/deregisters from TG). |
| **Linkerd sidecars** | Encrypt every pod-to-pod hop with mTLS. Auto-retry on transient 5xx. Emit metrics. |
| **Vault** | Issues short-lived DB creds on demand. Apps never store passwords. |
| **vault-agent sidecar** | (Inside each app pod that needs secrets.) Handles Vault login + secret fetch + lease renewal. |
| **Datadog agent** | Collects logs/metrics out-of-band. Doesn't sit in request path. |
| **Linkerd-viz** | Dashboard showing service-graph latency. Out-of-band. |
| **ArgoCD** | Idle at request time. Only acts when Git changes (re-syncs k8s state). |
| **EKS control plane** | Idle. Only acts when pods are created/deleted. |
| **RDS** | Stores actual data. Returns rows. |

### What fails if a component dies

| If this dies | Effect on user requests |
|---|---|
| **ALB** | All traffic stops. Single point of failure (mitigate with multi-AZ — already done) |
| **All frontend pods** | 503 from ALB |
| **Single frontend pod** | TG marks unhealthy, ALB skips it. No user impact (other replicas handle) |
| **Linkerd control plane** | Existing connections keep working (sidecars cache config). New pods can't get certs → eventually fail to start |
| **Vault** | Apps can't fetch new DB creds. Existing leases keep working until expiry (~1h). After that, DB calls fail |
| **RDS** | DB queries fail → 500s for any endpoint that hits Postgres |
| **Datadog** | No observability, but request flow unaffected |
| **ArgoCD** | No deployments possible. Running apps unaffected |
| **Linkerd-viz** | Dashboard unavailable. mTLS still works (control plane runs Linkerd-viz separately) |

This blast-radius table is the value of the architecture: each component fails independently. None take down the whole system.

---

## Vault deep dive — full secret lifecycle

Vault is the most-asked-about piece. This section covers every Vault flow end-to-end:

1. First-time init (one-time)
2. Auto-unseal on every pod restart
3. How operators read the root token
4. How `vault-config` unit configures Vault during apply
5. How apps fetch dynamic DB creds at runtime
6. Day-2 ops: rotation, lease cleanup, recovery
7. Disaster recovery (KMS unseal fails)

### 1. First-time init (apply phase, runs once ever)

```mermaid
sequenceDiagram
    autonumber
    participant TG as Terragrunt apply
    participant TF as Terraform
    participant K8s as Kubernetes
    participant V0 as vault-0 pod
    participant KMS as AWS KMS
    participant SSM as AWS SSM
    participant Sh as scripts/vault-init.sh

    TG->>TF: apply units/vault
    TF->>K8s: helm install vault (3 pods)
    Note over V0: Pods start sealed.<br/>"Sealed" = encrypted at rest,<br/>can't read/write secrets
    TF->>SSM: PutParameter root-token = "placeholder"
    TF->>SSM: PutParameter recovery-key-{0..4} = "placeholder"
    TF-->>TG: TF apply done
    TG->>Sh: after_hook fires bash scripts/vault-init.sh
    Sh->>V0: kubectl wait Running
    Sh->>V0: vault status -format=json
    alt initialized=true (re-apply)
        Sh-->>TG: exit 0 (skip)
    else initialized=false (first time)
        Sh->>V0: vault operator init -recovery-shares=5 -recovery-threshold=3
        V0->>KMS: GenerateDataKey (auto-unseal master key)
        KMS-->>V0: encrypted unseal key
        V0-->>Sh: { root_token, recovery_keys[5] }
        Note over V0: Vault now unsealed,<br/>raft cluster forming
        Sh->>SSM: PutParameter --overwrite root-token = "<real-token>"
        Sh->>SSM: PutParameter --overwrite recovery-key-{0..4} = "<real-keys>"
    end
```

**Key facts:**

- `vault operator init` runs **once for the lifetime of the Vault cluster**. Re-running on initialized Vault is a no-op (script's `initialized=true` check).
- The 5 recovery keys are a Shamir secret-shared backup. To unseal Vault manually (if KMS dies), an operator needs at least **3 of 5** keys.
- Auto-unseal means: every time a Vault pod restarts, it asks AWS KMS to decrypt its on-disk seal key. No manual unseal needed in normal ops.

### 2. Auto-unseal on every pod restart (runs on every pod boot)

```mermaid
sequenceDiagram
    autonumber
    participant K8s as Kubernetes
    participant Pod as vault-N pod
    participant KMS as AWS KMS
    participant Raft as Raft cluster (vault-0,1,2)

    K8s->>Pod: pod scheduled (e.g. node restart)
    Pod->>Pod: read /vault/data raft state (sealed)
    Pod->>KMS: Decrypt(seal_key_ciphertext)
    Note over KMS: IRSA: pod's ServiceAccount<br/>assumes vault IAM role<br/>via OIDC (no creds in pod)
    KMS-->>Pod: plaintext seal key
    Pod->>Pod: derive master key, unseal raft
    Pod->>Raft: rejoin cluster as follower (or leader)
    Raft-->>K8s: pod reports Ready
```

**Why IRSA matters:** the Vault pod has no AWS access keys in env or volumes. The IAM role is mapped to the `vault` ServiceAccount (set up by `units/vault-irsa`). When the pod calls KMS, AWS validates the OIDC token from the pod's ServiceAccount and grants temporary credentials. Zero secrets in the pod itself.

### 3. How operators read the root token (manual)

After init, the root token lives in SSM. Operators retrieve it via:

```bash
# One-shot read (from any machine with AWS creds)
aws ssm get-parameter \
  --name /terragrunt-infra/vault/root-token \
  --with-decryption \
  --query Parameter.Value \
  --output text
```

Or set up a Vault session for `make` targets:

```bash
source scripts/load_env.sh production   # exports VAULT_TOKEN + VAULT_ADDR

make vault-status      # health check
make vault-db-creds    # generate dynamic DB cred (test)
make vault-rotate-db   # rotate the DB root password Vault uses
```

The Makefile (`makefiles/vault.mk`) port-forwards `vault` service to `localhost:18200` and uses the token to call Vault's HTTP API.

### 4. `vault-config` unit configures Vault (apply phase)

Right after init succeeds, the `vault-config` unit runs (Layer 5). It reads the root token from SSM and configures Vault:

```mermaid
sequenceDiagram
    autonumber
    participant TF as Terraform (vault-config unit)
    participant SSM as AWS SSM
    participant V as Vault API
    participant DB as RDS Postgres

    TF->>SSM: GetParameter root-token (data source)
    SSM-->>TF: <root-token>
    Note over TF: Configure Terraform vault provider<br/>using this token

    TF->>V: enable database secrets engine (path=payments-app/database)
    TF->>V: enable kv-v2 secrets engine (path=secrets/)
    TF->>V: enable pki secrets engine (paths: consul/server/pki, etc)
    TF->>V: write database/config/payments (postgres:// URL + admin creds)
    TF->>V: write database/roles/payments (creation_statements, TTL=1h)
    TF->>DB: (Vault) test connection
    TF->>V: enable kubernetes auth method (path=k8s)
    TF->>V: write kubernetes/config (cluster CA + JWT)
    TF->>V: write kubernetes/role/payments<br/>(bound to ServiceAccount payments-app/payments)
    TF->>V: write policy "payments-read"<br/>(read database/creds/payments)
    TF->>V: attach policy to k8s role
```

Once this runs, Vault knows:
- How to talk to RDS (admin creds, role templates)
- Which Kubernetes ServiceAccounts can authenticate
- Which secrets each authenticated identity can read

### 5. App fetches dynamic creds at runtime (request flow recap)

Already covered in the request lifecycle above. Quick recap:

```mermaid
sequenceDiagram
    autonumber
    participant App as payments-app pod
    participant Agent as vault-agent sidecar
    participant V as Vault
    participant DB as RDS

    Note over App: pod starts
    Agent->>V: POST auth/k8s/login<br/>{role:payments, jwt:<SA-token>}
    V->>V: TokenReview API call to k8s
    V-->>Agent: vault token (TTL=1h)
    Agent->>V: GET database/creds/payments
    V->>DB: CREATE USER tmp_xyz WITH PASSWORD ...
    V->>DB: GRANT SELECT, INSERT ... TO tmp_xyz
    V-->>Agent: { username, password, lease_id, ttl=3600 }
    Agent->>App: write /vault/secrets/database.properties
    App->>App: read file, connect to DB
    App->>DB: queries using tmp_xyz

    loop Every 30 min
        Agent->>V: PUT sys/leases/renew (lease_id)
        V-->>Agent: lease extended
    end

    Note over Agent: Eventually app pod terminates
    Agent->>V: revoke lease
    V->>DB: DROP USER tmp_xyz
```

Static passwords never exist. If a pod is compromised, the worst case is a 1-hour-valid DB user, automatically revoked when the lease expires.

### 6. Day-2 operations

| Task | Command | Effect |
|---|---|---|
| View Vault health | `make vault-status` | Returns sealed/unsealed, leader, version |
| Generate test DB creds | `make vault-db-creds APP=payments-app` | Vault issues a fresh ephemeral user |
| Rotate DB root password | `make vault-rotate-db APP=payments-app` | Vault generates new admin password, updates RDS, updates own config. Apps unaffected |
| Force-revoke all DB leases | `make vault-lease-clean APP=payments-app` | Drops all dynamic users immediately. Use during incident |
| Manually unseal | `kubectl exec vault-0 -- vault operator unseal <key>` × 3 | Only needed if KMS auto-unseal fails (see DR section) |
| View PKI cert chain | `make vault-pki-roots` | Shows internal CA chain |

### 7. Disaster recovery — KMS auto-unseal fails

```mermaid
flowchart TB
    Start[Vault pod restarts] --> Try{Try auto-unseal<br/>via AWS KMS}
    Try -->|Success| Up[Pod Ready, raft online]
    Try -->|KMS unreachable<br/>or key deleted| Sealed[Pod stays sealed,<br/>not Ready]

    Sealed --> Op[Operator action required]
    Op --> Get[aws ssm get-parameter recovery-key-0..4]
    Get --> Manual[kubectl exec vault-0 --<br/>vault operator unseal &lt;key&gt;<br/>repeat with 3 of 5 keys]
    Manual --> Up

    style Sealed fill:#fdd
    style Up fill:#dfd
```

Recovery keys (the 5 stored in SSM) are the manual fallback. Why we keep them:

- AWS KMS could theoretically be unavailable (rare)
- Someone could accidentally delete the unseal KMS key
- Account-level access loss → last-resort recovery

**To unseal manually:**

```bash
# 1. Fetch 3 recovery keys
for i in 0 1 2; do
  aws ssm get-parameter \
    --name /terragrunt-infra/vault/recovery-key-$i \
    --with-decryption --query Parameter.Value --output text
done

# 2. Run unseal 3 times (one per key)
kubectl exec vault-0 -n vault -- vault operator unseal <key-0>
kubectl exec vault-0 -n vault -- vault operator unseal <key-1>
kubectl exec vault-0 -n vault -- vault operator unseal <key-2>

# 3. Repeat for vault-1, vault-2 if needed
```

### Vault component map

```mermaid
flowchart LR
    subgraph AWS
        KMS[KMS unseal key]
        SSM[(SSM<br/>root-token<br/>recovery-keys)]
        IAM[Vault IAM role<br/>via IRSA]
    end

    subgraph K8s [Kubernetes]
        SA[ServiceAccount: vault]
        SS[StatefulSet: vault-0/1/2]
        Agent[vault-agent sidecar<br/>in app pods]
    end

    subgraph V [Vault internals]
        Raft[Raft storage<br/>encrypted at rest]
        Auth[k8s auth method]
        DBEng[Database secrets engine]
        PKI[PKI engine]
    end

    SA -->|IRSA OIDC| IAM
    IAM -->|kms:Decrypt| KMS
    KMS -.unseals.-> SS
    SS -.persists.-> Raft

    Agent -->|login| Auth
    Auth -->|TokenReview| SA
    Agent -->|generate| DBEng
    DBEng -->|CREATE USER| RDS[(RDS)]

    Op[Operator] -->|aws ssm get-parameter| SSM
    SSM -.read by.-> Op
```

### TL;DR for non-experts

- **Vault** = secret vault. Apps don't store passwords; they ask Vault for fresh ones.
- **Sealed/unsealed** = locked/unlocked. We use AWS KMS to unlock automatically.
- **Root token** = master admin key. Stored in AWS SSM (encrypted). Operators fetch it on demand.
- **Recovery keys** = 5 backup keys. Need 3 to manually unlock if AWS KMS dies. Stored in SSM.
- **Dynamic DB creds** = Vault creates a new DB user for each app session, deletes it after 1 hour. No password ever stored in app.
- **vault-agent** = sidecar in app pods. Logs into Vault using k8s identity, fetches secrets, writes them to a file the app reads.
