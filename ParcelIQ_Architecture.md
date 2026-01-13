# ParcelIQ — Architecture (Kubernetes on AWS, Python Microservices)

**Document version:** v1  
**Aligned requirements:** ParcelIQ Requirements v2 (Sentinel-integrated)  
**Last updated:** 2026-01-13

---

## 1) Purpose and scope

This document describes the recommended production architecture for **ParcelIQ**, based on:
- the updated ParcelIQ requirements (v2) with mandatory **Sentinel** adoption, and
- the proposed small **micro-service** architecture (Python services deployed to Kubernetes on AWS).

It focuses on:
- service boundaries and responsibilities,
- request and event flows,
- data ownership and storage,
- Sentinel-based identity/permissions/audit/rate limiting integration,
- deployment, scaling, resiliency, observability, and security controls.

---

## 2) Architectural goals

### 2.1 Primary goals
- **Carrier-agnostic external API** (EasyPost-like) that supports validation, rating, shipment creation, purchase/void, reroute, tracking, pickups/manifests/batches, webhooks, reporting, billing, reconciliation, and claims.
- **Strong multi-tenant isolation**: all data, policies, and rate limits are tenant-scoped.
- **Centralized security controls**: all AuthN/AuthZ/audit/rate limiting is enforced via **Sentinel** (Cedar) with a **fail-closed** posture.
- **Operational simplicity**: keep micro-service count **small**, with clear, stable responsibilities.
- **High concurrency**: support **tens of requests/second per account**, and **thousands of accounts concurrently** via horizontal scaling and caching.
- **Bounded growth**: active data does not grow unbounded; completed shipments older than policy (e.g., 3 months) are migrated to archival storage while remaining accessible (with potential delay).

### 2.2 Non-goals (initial)
- Building a full customer-facing OMS/WMS UI suite (beyond basic admin/ops dashboards).
- Implementing a carrier marketplace or end-customer delivery experience.
- Real-time bidding optimization beyond deterministic routing rules (this can be added later).

---

## 3) High-level system context

### 3.1 External actors
- **Customer Systems / Integrations**: eCommerce platforms, OMS/WMS, marketplace backends.
- **Customer Admin/Operators**: using ParcelIQ dashboard or API.
- **Carriers**: FedEx, UPS, USPS, Amazon Shipping, etc.
- **Sentinel**: centralized security (AuthN/AuthZ/audit/rate limiting/request signing/security-state).

### 3.2 Context diagram (logical)

```mermaid
flowchart LR
  Client[Customer API Clients / UI] --> Edge[parceliq-edge (Public API)]
  Edge --> Sentinel[Sentinel (AuthN/AuthZ/Audit/Rate Limit)]
  Edge --> Shipping[parceliq-shipping]
  Edge --> Pricing[parceliq-pricing]
  Edge --> Billing[parceliq-billing]

  Shipping --> Carrier[parceliq-carrier]
  Pricing --> Carrier

  Shipping --> Events[parceliq-events]
  Pricing --> Events
  Billing --> Events

  Events --> Webhooks[Customer Webhook Endpoints]
  Carrier --> Carriers[Carrier APIs]

  Events --> Bus[(Kafka/MSK or SNS+SQS)]
  Bus --> Billing
  Bus --> Shipping
```

---

## 4) Service inventory (small and clear)

> Total ParcelIQ services: **6** (plus **Sentinel** as a required external micro-service)

| Service | Purpose | Primary data ownership |
|---|---|---|
| **parceliq-edge** | Public API gateway and **primary policy enforcement point (PEP)** | Idempotency records, request metadata (minimal) |
| **parceliq-shipping** | Shipment workflow/state machine + operational actions | Shipments, labels, trackers, batches, manifests, pickups |
| **parceliq-carrier** | Carrier adapters + credential usage + normalization | Carrier accounts, credential references, carrier capability metadata |
| **parceliq-pricing** | Rating + routing + virtual services + deterministic quotes | Rate tables, routing policies, quote records |
| **parceliq-billing** | Ledger + invoices + reconciliation + claims | Ledger entries, invoices, reconciliation runs, claims |
| **parceliq-events** | Eventing adapter + webhook delivery + archival jobs | Webhook endpoints/delivery, archive index, durable outbox publisher |
| **Sentinel** | AuthN/AuthZ (Cedar), audit/events, rate limiting primitives, security state | Identity, tokens, policies, audit/event pipeline |

---

## 5) Core cross-cutting patterns

### 5.1 Multi-tenancy
- **Tenant** is the top-level boundary. Every request must resolve a `tenant_id`.
- `tenant_id` may be derived from:
  - Sentinel token claims (preferred), and/or
  - explicit tenant header for service principals where applicable (validated).
- All persistent data includes `tenant_id` as a partition key (logical and/or physical).

### 5.2 Correlation IDs
- **parceliq-edge** accepts `X-Request-Id` and `X-Correlation-Id` or generates them.
- Correlation identifiers are propagated to:
  - all service logs and traces,
  - all downstream service calls,
  - all emitted events and webhooks,
  - Sentinel audit/events.

### 5.3 Idempotency
- All write endpoints accept `Idempotency-Key`.
- `parceliq-edge` provides request-level idempotency for public writes.
- `parceliq-shipping` enforces domain-level idempotency for label purchase/void/reroute (protect against retries and bus replays).
- For “money-moving” operations, idempotency is enforced with stable keys derived from:
  - `(tenant_id, shipment_id, operation, client_idempotency_key)`.

### 5.4 Outbox + event-driven side effects
- Services that produce events write both:
  1) domain transaction changes, and  
  2) an **outbox event row**  
  in the same database transaction.
- **parceliq-events** reads outbox tables and publishes to the message bus.
- Consumers (e.g., billing) are built to be **idempotent**.

### 5.5 Resiliency defaults
- Strict timeouts on all service-to-service calls.
- Retries with exponential backoff for safe operations only.
- Circuit breakers for carrier APIs and bus publishing.
- Fail-closed for security decisions (Sentinel).

---

## 6) Sentinel integration (required)

### 6.1 Authentication (AuthN)
- Clients authenticate using `Authorization: Bearer <token>` issued by **Sentinel**.
- Supported principals:
  - **User tokens** (interactive admin/ops UI)
  - **Service principals** (API keys mapped to Sentinel service principals/tokens)

### 6.2 Authorization (AuthZ) via Cedar (`/v1/authorize`)
Every protected operation is authorized using:
- `principal`: Sentinel `EntityUid` (user/service)
- `action`: stable action id (e.g., `create_shipment`, `purchase_label`, `manage_roles`)
- `resource`: stable resource `EntityUid` (e.g., `Shipment::"shp_123"`)
- `context`: ABAC fields and request metadata

**Fail-closed** rules:
- If Sentinel is unavailable for a protected action → deny.
- If operation mapping / resource extraction fails → deny.
- If Sentinel security-state indicates quarantined/blocked → deny.

### 6.3 Resource Registry mapping
ParcelIQ maintains Sentinel resource registry mappings for every externally exposed route:
- Route → action + resource type + resource id extraction rules
- ParcelIQ validates registry coverage at startup. Unmapped routes fail closed.

### 6.4 Auditing / security events
ParcelIQ emits security-relevant events to Sentinel (directly or via a pipeline), including:
- authentication/session events
- authorization allow/deny outcomes
- high-risk business actions (label purchases/voids/refunds, reroutes, carrier credential changes, billing adjustments, API key lifecycle)

---

## 7) Service designs (responsibilities, APIs, storage, events)

### 7.1 parceliq-edge (Public API + Primary PEP)
**Responsibilities**
- External API surface (REST; versioned)
- Request validation + normalization
- **Sentinel AuthN/AuthZ** enforcement, rate limiting
- Idempotency for public writes
- Correlation IDs
- Fan-out orchestration for “API facade” endpoints where needed (keep minimal)

**Public endpoints (examples)**
- `/v1/addresses/validate`
- `/v1/shipments` (create)
- `/v1/shipments/{id}` (read)
- `/v1/shipments/{id}/rates` (rate)
- `/v1/shipments/{id}/buy` (purchase label)
- `/v1/shipments/{id}/void`
- `/v1/shipments/{id}/reroute`
- `/v1/trackers/{id}`
- `/v1/webhooks`
- `/v1/invoices`, `/v1/ledger`, `/v1/reconciliation`
- `/v1/claims`

**Internal calls**
- Shipping, Pricing, Billing (sync)

**Data**
- Redis or Postgres table for idempotency keys and response cache (bounded TTL)

**Scaling**
- Horizontally scalable stateless pods behind an ingress controller / AWS Load Balancer.

---

### 7.2 parceliq-shipping (Shipment workflow/state machine)
**Responsibilities**
- Shipment lifecycle and state transitions:
  - created → rated → purchased → in_transit → delivered → completed
  - voided, returned, rerouted/intercepted as alternate states
- “Money-moving” operations with strict idempotency:
  - purchase label, void label, refunds (if applicable)
- Maintain artifacts: label URLs/blobs references, tracking numbers, manifests, pickups
- Emit domain events

**Key internal APIs**
- `POST /internal/shipments` (create)
- `GET /internal/shipments/{id}`
- `POST /internal/shipments/{id}/purchase`
- `POST /internal/shipments/{id}/void`
- `POST /internal/shipments/{id}/reroute`
- `POST /internal/shipments/{id}/pickup`
- `POST /internal/shipments/{id}/manifest`

**Data store**
- Postgres (shipments, state transitions, artifacts, outbox)

**Events produced**
- `ShipmentCreated`, `ShipmentUpdated`
- `LabelPurchased`, `LabelVoided`
- `ShipmentRerouted`, `PickupScheduled`, `ManifestCreated`
- `ShipmentArchived` (optional)

**Events consumed**
- Carrier async updates (optional): `CarrierTrackingUpdated`, `CarrierException`

---

### 7.3 parceliq-carrier (Carrier integrations)
**Responsibilities**
- Carrier adapter framework and per-carrier modules
- Credential usage and secure token handling
- Address validation (carrier-supported)
- Rate fetching (raw), label purchase/void, tracking, pickups/manifests
- Normalize carrier errors into ParcelIQ error taxonomy

**Key internal APIs**
- `POST /internal/carrier/validate_address`
- `POST /internal/carrier/get_rates`
- `POST /internal/carrier/purchase_label`
- `POST /internal/carrier/void_label`
- `POST /internal/carrier/track`
- `POST /internal/carrier/schedule_pickup`
- `POST /internal/carrier/create_manifest`

**Data store**
- Postgres (carrier accounts, credentials metadata, capabilities)
- Secrets stored in AWS Secrets Manager + KMS; service stores only references/metadata.

**Scaling**
- Horizontally scale; apply per-carrier concurrency limits to avoid carrier bans.

---

### 7.4 parceliq-pricing (Rating + routing + virtual services)
**Responsibilities**
- Deterministic rating results (quotes)
- Routing policy evaluation and “virtual services” abstraction
- Pricing adjustments: markups/markdowns/surcharges/minimums
- Quote caching and TTLs; explainability (“why this rate/route”)

**Key internal APIs**
- `POST /internal/quotes` (create/rate)
- `GET /internal/quotes/{id}`
- `POST /internal/routes/evaluate` (optional split if needed)

**Data store**
- Postgres (rate tables, routing policies, virtual services, quotes, outbox)
- Redis (quote cache)

**Events produced**
- `QuoteGenerated`, `RouteChosen` (optional, recommended for audit)

---

### 7.5 parceliq-billing (Ledger + invoices + reconciliation + claims)
**Responsibilities**
- Append-only ledger (with controlled adjustment entries)
- Invoices and statements
- Carrier invoice ingestion and matching
- Reconciliation workflows and outcomes
- Claims tracking and financial outcomes

**Key internal APIs**
- `GET /internal/ledger`
- `POST /internal/ledger/adjust`
- `GET /internal/invoices`
- `POST /internal/reconciliation/run`
- `POST /internal/claims`

**Data store**
- Postgres (ledger, invoices, claims, reconciliation)
- S3 (exports, invoice PDFs, evidence files)

**Events consumed**
- `LabelPurchased` → ledger debit
- `LabelVoided` → ledger credit/adjustment
- `ShipmentRerouted` (if billable)
- Any manual adjustment events from admin tooling

**Events produced**
- `InvoiceIssued`, `LedgerAdjusted`, `ReconciliationCompleted`, `ClaimClosed`

---

### 7.6 parceliq-events (Bus adapter + webhooks + archival)
**Responsibilities**
- Publish events from service outboxes to the bus
- Webhook endpoint management and delivery (retries, signing, DLQ)
- Scheduled archival of “completed old orders”
- Optional: forward audit/security-relevant events into Sentinel event pipeline

**Key internal APIs**
- `POST /internal/webhooks` / `GET /internal/webhooks`
- `POST /internal/events/replay` (admin-only)
- `POST /internal/archive/run` (admin/scheduled)

**Data store**
- Postgres (webhook endpoints, deliveries, outbox cursors, archive index)
- S3 (archived objects, exports)

**Bus**
- Prefer **SNS/SQS** for simpler ops; use **MSK (Kafka)** if high throughput + ordering needs are strong.

---

## 8) Data architecture and ownership

### 8.1 Database strategy
- Each service owns its domain schema. Recommended:
  - One Aurora Postgres cluster with separate databases/schemas per service (initial simplicity)
  - Option to split into separate clusters later if required by scale or compliance
- Strong tenant partitioning:
  - indexes always include `tenant_id`
  - avoid cross-tenant joins; service boundaries enforce isolation

### 8.2 Archival strategy (bounded growth)
- Completed shipments older than retention window (e.g., 90 days) are:
  - serialized to a compact archival format (JSON/Parquet) and stored in **S3** (optionally Glacier tiering)
  - indexed in `parceliq-events` archive index (tenant_id + shipment_id + location + metadata)
- Reads for archived items:
  - `parceliq-shipping` detects archived state and either:
    - rehydrates into cache, or
    - returns “loading” response with polling token (implementation choice)
- Auditing and access control still apply on archived reads.

---

## 9) API and event contracts

### 9.1 External API contract
- REST JSON, versioned `/v1`
- Idempotency on all writes
- Deterministic, normalized error shapes
- Webhook delivery with signing + replay protection

### 9.2 Internal API contract
- Prefer **gRPC** for internal service-to-service calls (typed contracts + performance), but REST is acceptable initially.
- Internal endpoints are authenticated as service principals and authorized via Sentinel where appropriate.

### 9.3 Event contract
- Events are immutable facts with:
  - `event_id`, `event_type`, `tenant_id`, `occurred_at`
  - `principal_id` (if applicable)
  - `resource_ids`
  - `correlation_id`
  - `payload_version`
- Consumers must be idempotent by `event_id`.

---

## 10) Key flows

### 10.1 Rate shipment
1. Client → **edge** `POST /v1/shipments/{id}/rates`
2. Edge → Sentinel authorize + rate limit
3. Edge → Pricing `POST /internal/quotes`
4. Pricing → Carrier `get_rates`
5. Pricing applies routing + pricing rules → returns quotes to edge
6. Pricing emits `QuoteGenerated` (optional)

### 10.2 Purchase label
1. Client → **edge** `POST /v1/shipments/{id}/buy` + `Idempotency-Key`
2. Edge authorizes `purchase_label(Shipment::id)` and enforces idempotency
3. Edge → Shipping `POST /internal/shipments/{id}/purchase`
4. Shipping validates state; may request updated quote from Pricing; calls Carrier `purchase_label`
5. Shipping persists label + emits `LabelPurchased` via outbox
6. Events publishes; Billing consumes → ledger entry; Events delivers webhooks

### 10.3 Void label
- Similar, with strict idempotency and ledger adjustments.

### 10.4 Reconciliation
- Billing ingests carrier invoices, matches against ledger, produces outcomes and events.

### 10.5 Archived read
- Edge authorizes read; Shipping detects archived; fetches from S3 (may be slower) and returns.

---

## 11) Deployment architecture (AWS + EKS)

### 11.1 Kubernetes (EKS)
- One EKS cluster per environment (dev/stage/prod)
- Namespaces:
  - `parceliq` (app services)
  - `sentinel` (if operated in-cluster) or VPC endpoint to managed Sentinel deployment
  - `observability` (collector, metrics)

### 11.2 Ingress
- AWS Load Balancer Controller → ALB → `parceliq-edge`
- Only `parceliq-edge` is public.

### 11.3 AWS managed services
- **Aurora Postgres**: primary OLTP stores (per-service schemas)
- **ElastiCache Redis**: caching, idempotency, rate limit backends
- **S3**: archival, exports, invoice PDFs, evidence documents
- **MSK** or **SNS/SQS**: event bus
- **Secrets Manager + KMS**: carrier credentials, signing keys
- **CloudWatch** + **OpenTelemetry** collector for logs/metrics/traces

### 11.4 Scaling targets
- HPA on CPU/RPS for edge/shipping/pricing/carrier
- Queue depth scaling for events and billing consumers
- Concurrency limits per carrier to avoid throttling/bans

---

## 12) Security architecture

### 12.1 Data protection
- TLS everywhere (ingress + service mesh optional)
- Encrypt PII and credentials at rest (KMS-managed)
- Strict secrets access: only `parceliq-carrier` can access raw carrier credentials.

### 12.2 Request signing + replay protection (internal)
- Sensitive service-to-service calls use request signing with nonce + timestamp checks.

### 12.3 Audit and compliance posture
- Sentinel receives immutable audit/security events.
- ParcelIQ emits domain events for business auditing and reconciliation.
- PII minimization and retention policies apply to both active and archived data.

---

## 13) Observability and operations

### 13.1 Logging
- JSON structured logs
- Mandatory fields: `request_id`, `correlation_id`, `tenant_id`, `principal_id`, `service`, `route`, `action`, `resource`

### 13.2 Tracing
- OpenTelemetry tracing across edge → services → carrier calls
- Trace propagation includes correlation IDs

### 13.3 Metrics
- Golden signals per service:
  - latency, error rate, saturation, throughput
- Business metrics:
  - labels purchased, void rate, carrier error rate, quote hit rate, reconciliation match rate

### 13.4 Runbooks
- Sentinel outage: fail-closed for protected actions; operational runbook for mitigation
- Carrier degradation: circuit breakers + fallback carriers/rules where possible

---

## 14) Appendix A — Minimum resources and actions (Sentinel)

### 14.1 Resource types
- `Tenant`, `User`, `Service`
- `CarrierAccount`, `CarrierCredential`
- `Shipment`, `RateQuote`, `Label`, `Tracker`, `Batch`, `Manifest`, `Pickup`
- `VirtualService`, `RoutingPolicy`
- `Invoice`, `LedgerEntry`, `ReconciliationRun`, `Claim`
- `WebhookEndpoint`, `ReportExport`

### 14.2 Action families
- Read/list/export: `read`, `list`, `export`
- Shipping: `create_shipment`, `rate_shipment`, `purchase_label`, `void_label`, `reroute_shipment`, `create_return`, `schedule_pickup`, `create_manifest`, `batch_purchase`
- Billing: `manage_billing`, `create_invoice`, `adjust_ledger`, `run_reconciliation`
- Admin/security: `manage_users`, `manage_roles`, `manage_api_keys`, `manage_carriers`, `manage_policies`

---

## 15) Appendix B — Implementation recommendations (Python)

- **Framework**: FastAPI for edge + internal services (or gRPC where preferred)
- **Async IO**: async clients for carrier APIs (httpx/aiohttp) to maximize throughput
- **DB layer**: SQLAlchemy + Alembic migrations per service
- **Messaging**: SNS/SQS consumer workers via asyncio or Celery/RQ; Kafka via aiokafka if MSK is chosen
- **Policy enforcement**: a shared internal library for:
  - extracting principal/action/resource/context
  - calling Sentinel `/authorize`
  - enforcing fail-closed rules consistently

---

### Notes
- This architecture intentionally minimizes service count while preserving clear boundaries.
- Service boundaries align to domains: Edge (API + PEP), Shipping (workflow), Carrier (integrations), Pricing (rating/routing), Billing (money), Events (async/webhooks/archival), with Sentinel as the security backbone.
