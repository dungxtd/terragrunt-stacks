# Platform Components — Production Flow

Four core infra components and how they interact in production.

---

## Network Flow — Request from Internet

### Topology (where traffic physically goes)

```mermaid
flowchart LR
    subgraph Internet
        Client([Browser / API Client])
    end

    subgraph AWS ["AWS — ap-southeast-1"]
        ALB["AWS ALB\nTLS termination\n(ACM cert)"]

        subgraph EKS ["EKS Cluster"]
            subgraph GW ["Gateway API"]
                GWRes["Gateway\n(aws-load-balancer-controller)"]
                HR["HTTPRoute\nstable 90% / canary 10%\n(Flagger-managed)"]
            end

            subgraph NSApp ["Namespace: payments-app"]
                subgraph PodStable ["Pod: payments-app-stable"]
                    LP1["linkerd-proxy\n(sidecar)"]
                    App1["payments-app\ncontainer"]
                    VA1["vault-agent\n(sidecar)"]
                end
                subgraph PodCanary ["Pod: payments-app-canary"]
                    LP2["linkerd-proxy\n(sidecar)"]
                    App2["payments-app\ncontainer"]
                    VA2["vault-agent\n(sidecar)"]
                end
            end

            subgraph NSVault ["Namespace: vault"]
                VaultHA["Vault HA\n(3 replicas, Raft)"]
            end

            subgraph NSLinkerd ["Namespace: linkerd-viz"]
                Prom["Prometheus"]
            end

            subgraph NSFlagger ["Namespace: flagger-system"]
                Flagger["Flagger\ncanary controller"]
            end

            subgraph NSConsul ["Namespace: consul"]
                ConsulSvr["Consul Server\ncatalog / DNS"]
            end
        end

        subgraph AWS2 ["AWS Services"]
            RDS["PostgreSQL RDS"]
            KMS["KMS\nauto-unseal"]
            SSM["SSM Parameter Store\nroot token · keys"]
        end
    end

    Client -->|"HTTPS :443"| ALB
    ALB -->|"HTTP"| GWRes
    GWRes --> HR
    HR -->|"90%"| LP1
    HR -->|"10%"| LP2
    LP1 <-->|"mTLS\n(SPIFFE cert)"| App1
    LP2 <-->|"mTLS\n(SPIFFE cert)"| App2
    App1 -->|"unix socket"| VA1
    App2 -->|"unix socket"| VA2
    VA1 -->|"k8s SA token auth\ndynamic DB creds"| VaultHA
    VA2 -->|"k8s SA token auth\ndynamic DB creds"| VaultHA
    App1 -->|"transit encrypt/decrypt"| VaultHA
    VaultHA -->|"CREATE ROLE TTL=1h"| RDS
    App1 -->|"jdbc (dynamic creds)"| RDS
    App2 -->|"jdbc (dynamic creds)"| RDS
    VaultHA <-->|"auto-unseal"| KMS
    VaultHA -->|"store init keys"| SSM
    LP1 & LP2 -->|"metrics scrape"| Prom
    Prom -->|"success-rate / p99"| Flagger
    Flagger -->|"adjust weights"| HR
    App1 & App2 -.->|"DNS lookup"| ConsulSvr
```

### Request lifecycle (step by step)

```mermaid
sequenceDiagram
    actor Client as Client<br/>(Internet)
    participant ALB as AWS ALB
    participant GW as Gateway<br/>(HTTPRoute)
    participant LP as linkerd-proxy<br/>(sidecar)
    participant App as payments-app
    participant VA as vault-agent<br/>(sidecar)
    participant Vault as Vault HA
    participant RDS as PostgreSQL

    Client->>ALB: HTTPS (TLS terminated at ALB)
    ALB->>GW: HTTP → target pod (90% stable / 10% canary)
    GW->>LP: forward request
    Note over LP: Linkerd intercepts all inbound traffic.<br/>If caller also has linkerd-proxy → mTLS.<br/>ALB has no sidecar → plaintext from ALB.
    LP->>App: HTTP (plaintext to app container)

    alt DB credential not yet on disk
        App->>VA: read /vault/secrets/db-creds
        VA->>Vault: GET /v1/payments-app/database/creds/payments
        Vault->>RDS: CREATE ROLE v-k8s-payments-XXXX TTL=1h
        Vault-->>VA: {username, password}
        VA-->>App: write /vault/secrets/db-creds
    end

    App->>RDS: query (dynamic creds, TTL=1h)
    RDS-->>App: result

    opt sensitive field (card number, etc.)
        App->>Vault: POST /v1/transit/encrypt/payments-app
        Vault-->>App: ciphertext
    end

    App-->>LP: HTTP response
    LP-->>ALB: response
    ALB-->>Client: HTTPS response

    Note over LP: linkerd-proxy records:<br/>latency, success/error rate → Prometheus
```

### Canary promotion flow (background, parallel to live traffic)

```mermaid
sequenceDiagram
    participant CI as CI/CD Pipeline
    participant F as Flagger
    participant HR as HTTPRoute
    participant P as linkerd-viz<br/>Prometheus
    participant Stable as payments-app-stable
    participant Canary as payments-app-canary

    CI->>Stable: Update image tag (triggers Flagger)
    F->>Canary: Create canary Deployment (new image)
    F->>HR: Set weights: stable=90 canary=10

    loop 5 × 30s checks
        P-->>F: success_rate(canary), p99_latency(canary)
        alt healthy (success≥99%, p99≤500ms)
            F->>HR: stable -= 10, canary += 10
        else unhealthy
            F->>HR: stable=100, canary=0
            F->>Canary: Delete canary Deployment
            Note over F: ❌ Rollback complete
        end
    end

    F->>Stable: Replace stable image with canary image
    F->>Canary: Delete canary Deployment
    Note over F: ✅ Promotion complete
```

---

## 1. Linkerd (Service Mesh)

**Role**: mTLS between pods, traffic metrics, canary traffic splitting via Flagger.

### Sidecar injection + mTLS

```mermaid
sequenceDiagram
    participant K8s as Kubernetes API
    participant W as Admission Webhook<br/>(proxy-injector)
    participant A as Pod A<br/>(linkerd-proxy sidecar)
    participant B as Pod B<br/>(linkerd-proxy sidecar)
    participant ID as Identity Service

    K8s->>W: Pod create (namespace inject=enabled)
    W-->>K8s: Mutate: add linkerd-proxy container

    A->>ID: Request mTLS cert (SPIFFE)
    B->>ID: Request mTLS cert (SPIFFE)
    ID-->>A: Short-lived cert
    ID-->>B: Short-lived cert

    A->>B: HTTP (app layer)
    Note over A,B: linkerd-proxy↔linkerd-proxy<br/>automatic mTLS, app sees plaintext
```

### Metrics flow (Flagger reads Prometheus)

```mermaid
flowchart LR
    PA[payments-app proxy] -->|scrape| P[linkerd-viz\nPrometheus]
    PC[payments-app canary proxy] -->|scrape| P
    P -->|query success-rate / p99| F[Flagger]
    F -->|shift HTTPRoute weights| R[HTTPRoute]
```

### Namespaces

| Namespace | What runs |
|-----------|-----------|
| `linkerd` | identity, proxy-injector, destination |
| `linkerd-viz` | Prometheus, tap, dashboard |
| `payments-app` | injected app pods |
| `flagger-system` | Flagger (needs Prometheus access) |

Flagger → Prometheus is blocked by default. `gitops/platform/linkerd-viz-policy/flagger-prometheus-authz.yaml` adds `AuthorizationPolicy` granting the `flagger` SA access to `prometheus-admin` Server.

---

## 2. Gateway API (Traffic Routing)

**Role**: Standard k8s routing CRDs. Replaces legacy Ingress. Required for Flagger canary.

### Resource hierarchy

```mermaid
graph TD
    GC[GatewayClass<br/>cluster-scoped<br/>'who handles traffic'] --> G
    G[Gateway<br/>'listener config'] --> H
    H[HTTPRoute<br/>'routing rules'] --> RG
    RG[ReferenceGrant<br/>'allow cross-ns backend refs']
```

### CRD bootstrap

`gitops/apps/gateway-api-crds.yaml` is wave 0 — it installs all standard CRDs from `kubernetes-sigs/gateway-api v1.2.1` before any other app syncs. Flagger cannot create `HTTPRoute` without these CRDs present.

### Canary traffic split (Flagger)

```mermaid
sequenceDiagram
    participant CD as CI/CD<br/>(new image tag)
    participant F as Flagger
    participant HR as HTTPRoute
    participant P as linkerd-viz<br/>Prometheus

    CD->>F: Deployment image changed
    F->>HR: Set weights stable=90 canary=10
    loop every 30s × 5 iterations
        F->>P: Query success-rate, p99 latency
        P-->>F: metrics
        alt metrics healthy
            F->>HR: Increase canary weight (+10%)
        else metrics bad
            F->>HR: weight=100% stable (rollback)
            F-->>CD: ❌ Canary failed
        end
    end
    F->>HR: weight=100% canary
    F-->>CD: ✅ Promoted
```

---

## 3. Vault (Secrets Management)

**Role**: Two distinct secret flows — dynamic DB credentials (short-lived) and static KV (synced via ESO).

### HA init flow (first deploy only)

```mermaid
sequenceDiagram
    participant TF as Terraform<br/>(vault unit)
    participant V as Vault Pod
    participant KMS as AWS KMS
    participant SSM as AWS SSM

    TF->>V: vault operator init
    V->>KMS: Encrypt unseal key
    V-->>TF: root token + recovery keys
    TF->>SSM: Store root token
    TF->>SSM: Store recovery keys (shamir)

    Note over V,KMS: On every pod restart:<br/>Vault → KMS auto-unseal<br/>(no manual intervention)
```

### Flow A — Dynamic DB credentials (payments-app)

```mermaid
sequenceDiagram
    participant Pod as payments-app pod
    participant VA as vault-agent<br/>(init container)
    participant V as Vault
    participant PG as PostgreSQL

    Pod->>VA: Start (init container runs first)
    VA->>V: POST /v1/auth/kubernetes/login<br/>serviceaccount: payments-app
    V-->>VA: Vault token (policy: payments-app)
    VA->>V: GET /v1/payments-app/database/creds/payments
    V->>PG: CREATE ROLE v-k8s-payments-XXXX TTL=1h
    V-->>VA: username + password
    VA->>Pod: Write to /vault/secrets/db-creds

    loop every ~45min (before TTL)
        VA->>V: Renew lease
    end
```

### Flow B — Static secrets via ExternalSecrets Operator

```mermaid
sequenceDiagram
    participant ESO as ExternalSecrets Operator
    participant V as Vault
    participant K8s as Kubernetes Secret

    ESO->>V: POST /v1/auth/kubernetes/login<br/>serviceaccount: external-secrets
    V-->>ESO: Vault token (policy: external-secrets-reader)
    ESO->>V: GET /v1/secret/data/datadog/api
    V-->>ESO: {api-key, app-key}
    ESO->>K8s: Create/Update Secret "datadog-api"

    Note over ESO,K8s: Sync every 1h.<br/>App pods mount k8s Secret normally.
```

### Transit encryption (payments-app)

```mermaid
flowchart LR
    App[payments-app] -->|POST /v1/transit/encrypt/payments-app\nplaintext| V[Vault]
    V -->|ciphertext| App
    App -->|POST /v1/transit/decrypt/payments-app\nciphertext| V
    V -->|plaintext| App
    Note[Vault holds key.\nApp never sees raw key material.]
```

### Secret paths summary

| Path | Engine | Consumer | How |
|------|--------|----------|-----|
| `payments-app/database/creds/payments` | database | payments-app | Vault Agent sidecar |
| `transit/encrypt(decrypt)/payments-app` | transit | payments-app | direct API call |
| `secret/data/datadog/api` | kv-v2 | datadog | ESO → k8s Secret |
| `secret/data/payments-app/*` | kv-v2 | payments-app | ESO → k8s Secret |
| `payments-processor/static/data/creds` | kv-v2 | payments-processor | Vault Agent sidecar |

---

## 4. Consul (Service Catalog)

**Role**: Service discovery catalog only. **No service mesh** (connectInject disabled).

### What it does

```mermaid
flowchart TD
    CC[consul-client\nDaemonSet, 1 per node] -->|register| CS[consul-server\nStatefulSet, 3 replicas\nRaft consensus]
    CS -->|sync| K8sSvc[k8s Services]
    App[Any app] -->|DNS: svc.service.consul\nor HTTP: /v1/catalog| CS
```

Consul does **not** inject sidecars or enforce mTLS — that is Linkerd's job. Consul owns catalog + DNS only.

### Why both Consul + Linkerd?

```mermaid
flowchart LR
    subgraph Consul
        C1[Service registration]
        C2[DNS: svc.service.consul]
        C3[Health checks]
    end
    subgraph Linkerd
        L1[mTLS between pods]
        L2[Traffic metrics]
        L3[Canary weight splits]
    end
    Note["Consul Connect disabled.\nNo dual-mesh conflict."]
```

Consul was the original mesh. Linkerd was added for stronger mTLS and k8s-native metrics. Consul Connect disabled to avoid conflicts. Consul serves catalog/DNS; Linkerd owns all mesh functionality.

---

## Full Component Interaction Map

```mermaid
graph TD
    subgraph ArgoCD ["ArgoCD — App-of-Apps"]
        W0[Wave 0\ngateway-api-crds]
        W1[Wave 1\nlinkerd · consul]
        W2[Wave 2\ndatadog]
        W3[Wave 3\nflagger · loadtester\nlinkerd-viz-policy]
        W4[Wave 4\npayments-app]
        W5[Wave 5\nplatform-ui]
        W0 --> W1 --> W2 --> W3 --> W4 --> W5
    end

    subgraph Infra ["AWS Infrastructure (Terraform + Terragrunt)"]
        EKS[EKS cluster]
        RDS[PostgreSQL RDS]
        KMS[KMS key\nVault auto-unseal]
        SSM[SSM Parameter Store\nroot token · recovery keys]
        ALB[ALB Ingress Controller]
    end

    subgraph Mesh ["Service Mesh (Linkerd)"]
        LP[linkerd-proxy\nsidecars]
        VIZ[linkerd-viz\nPrometheus]
    end

    subgraph Secrets ["Secrets (Vault HA)"]
        VA[Vault Agent\nsidecar]
        ESO[ExternalSecrets\nOperator]
        VaultCore[Vault\nHA Raft]
    end

    subgraph App ["payments-app"]
        Stable[stable deployment]
        Canary[canary deployment]
        HR[HTTPRoute\nstable/canary weights]
    end

    W0 -->|installs GW API CRDs| W1
    W3 -->|creates HTTPRoute| HR
    VIZ -->|metrics| W3
    LP -->|mTLS| App
    VA -->|dynamic DB creds| Stable
    VA -->|dynamic DB creds| Canary
    ESO -->|static secrets| App
    VaultCore -->|auto-unseal| KMS
    VaultCore -->|store init keys| SSM
    VaultCore -->|dynamic creds| RDS
    ALB -->|ingress| HR
```

---

## Deploy Order (ArgoCD Sync Waves)

```mermaid
gantt
    title ArgoCD Sync Wave Order
    dateFormat X
    axisFormat Wave %s

    section Bootstrap
    AppProject platform       :done, w-10, -10, -9
    Gateway API CRDs          :done, w0, 0, 1

    section Mesh & Catalog
    Linkerd control-plane     :done, w1a, 1, 2
    Consul                    :done, w1b, 1, 2

    section Observability
    Datadog                   :done, w2, 2, 3

    section Canary Controller
    Flagger                   :done, w3a, 3, 4
    Loadtester                :done, w3b, 3, 4
    linkerd-viz AuthzPolicy   :done, w3c, 3, 4

    section Application
    payments-app              :done, w4, 4, 5

    section Frontend
    platform-ui               :done, w5, 5, 6
```
