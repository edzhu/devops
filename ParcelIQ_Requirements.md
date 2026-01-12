# ParcelIQ — Detailed Requirements (v2)

> **Update (v2):** ParcelIQ MUST use the **Sentinel** repository as its centralized AuthN/AuthZ/audit platform.

## 0) Overview
ParcelIQ is a carrier-management and shipping-orchestration service that connects to multiple carriers (e.g., FedEx, UPS, USPS, Amazon Shipping, and others) and provides:
- A unified, EasyPost-like external API surface for shipping operations across carriers.
- A configurable rating engine that supports carrier published rates, account-specific rate adjustments, and peak/surcharge logic.
- Virtual services (user-defined shipping services) with flexible routing rules to one or more underlying carrier services.
- A prepaid balance + optional credit model with invoicing, reconciliation, and claims workflows.

**Primary users**
- Platform integrators (e-commerce platforms, marketplaces, WMS/OMS)
- Operations teams (shipping and billing/reconciliation)
- Developers (API clients)

**Core design principles**
- Carrier-agnostic external API
- Deterministic, auditable pricing
- Extensible routing rules
- Ledger-based billing and full traceability
- **Centralized security controls via Sentinel** (AuthN, AuthZ with Cedar, auditing, rate limiting, request signing)

---

## 1) Definitions (Canonical Terms)
- **Carrier**: A shipping provider (FedEx, UPS, USPS, Amazon Shipping, etc.).
- **Carrier Service**: A specific carrier offering (e.g., “UPS Ground”, “FedEx 2Day”).
- **Carrier Account**: A set of credentials + billing identifiers tied to a carrier (API key, account number, meter number, OAuth tokens, etc.).
- **Published Rate**: Carrier’s public price schedule (incl. base rates, zones, surcharges, effective dates).
- **Account-Level Rate Adjustment**: User-entered overrides/discounts/markups applied on top of published rates.
- **Virtual Service**: User-defined service name and pricing that maps to one or more carrier services.
- **Routing Policy**: Rules that choose which underlying carrier service fulfills a virtual service request.
- **Shipment**: The object representing an order for shipping labels, tracking, and related actions.
- **Transaction / Ledger Entry**: A financial record of charges, refunds, adjustments, and payments.
- **Carrier Invoice**: The carrier’s billed statement that may include adjustments after shipment is billed.
- **Claim**: A dispute process with a carrier (unknown shipment, undelivered, incorrect rating, etc.).
- **Tenant / Account (Tenant)**: The top-level organizational boundary in ParcelIQ. All users, API keys, carrier accounts, and shipments are scoped to a tenant.
- **Principal**: The identity requesting an operation (a **user** or a **service principal/API key**), represented as a Sentinel principal (e.g., `User::"u_123"` or `Service::"svc_abc"`).
- **Action**: A stable Sentinel action identifier (e.g., `read`, `create_shipment`, `purchase_label`, `void_label`, `manage_billing`) used for authorization checks.
- **Resource**: A stable Sentinel resource identifier (Cedar `EntityUid`) such as `Shipment::"shp_123"` or `CarrierAccount::"ca_456"`.
- **Role / Permission**: Tenant-scoped access rights expressed and enforced via Sentinel Cedar policies (roles may be implemented as groups/relationships + policy rules).
- **Sentinel**: The required security platform repository that provides centralized **AuthN**, **AuthZ** (Cedar), **audit/event emission**, **rate limiting**, **request signing**, and **security-state enforcement**.

---

## 2) External API (EasyPost-like) — Unified Across Carriers

### 2.1 General API Requirements
- **API style**: Versioned REST API with consistent, carrier-agnostic resource shapes (e.g., `Address`, `Parcel`, `Shipment`, `Rate`, `Tracker`, `Batch`, etc.).
- **AuthN (Sentinel)**: ParcelIQ MUST authenticate requests using **Sentinel-issued bearer tokens** (user tokens for human/UIs and service tokens for integrations). ParcelIQ MAY expose "API keys" to customers, but these MUST map to **Sentinel service principals/tokens** and be revocable/rotatable.
- **AuthZ (Sentinel/Cedar)**: Every protected operation MUST be authorized via **Sentinel** using the tuple `(principal, action, resource, context)` (typically by calling `POST /v1/authorize` or embedding Sentinel PEP middleware with equivalent semantics). Authorization MUST be **fail-closed**.
- **Correlation IDs (Sentinel-aligned)**: ParcelIQ MUST accept or generate `X-Request-Id` and MUST propagate a correlation identifier (e.g., `X-Correlation-Id`, defaulting to `X-Request-Id`) to all logs, downstream calls, webhooks, and Sentinel events.
- **Idempotency**: All write endpoints MUST support an `Idempotency-Key` to prevent duplicate labels/charges.
- **Pagination & filtering**: Standard query params for list endpoints; stable sorting.
- **Rate limiting (Sentinel)**: Enforce request throttling using Sentinel’s rate-limiting framework (Redis-backed in production). Limits MUST be configurable per tenant and per principal (user/service/API key), and MAY vary by endpoint/action. Responses MUST include clear `429` errors and SHOULD include `Retry-After` guidance.
- **Async processing**: Some operations MUST be modeled as asynchronous (e.g., batch operations) and expose status polling + webhook completion events.
- **Webhooks**: First-class webhook configuration, signed delivery support (e.g., HMAC), retry strategy, and event types covering all major object state changes (shipments, trackers, batches, claims, billing adjustments).
- **Error model**: Structured errors with machine-readable codes, human messages, and field-level validation errors.
- **Auditability**: Every pricing-affecting response MUST include a detailed breakdown and references to the rules/versions used.

### 2.1.1 Sentinel-based Identity, Permissions, and Enforcement (Required)

ParcelIQ MUST use the uploaded **Sentinel** repository as its **single** system of record and enforcement for:
- **User authentication (AuthN)** via OIDC Authorization Code + PKCE (handled by Sentinel’s `/v1/auth/*` + `/v1/token` flows).
- **Token issuance and refresh**, using Sentinel’s token service (user tokens and service tokens).
- **Authorization (AuthZ)** using **Cedar** policies evaluated by Sentinel’s PDP, invoked through Sentinel’s PEP `POST /v1/authorize`.
- **Permission / role management** via Cedar entity relationships (users, groups/roles, tenants, and ParcelIQ resources).
- **Immutable audit events** for all AuthN and AuthZ decisions, plus high-sensitivity ParcelIQ domain events.
- **Security enforcement state** (e.g., quarantined/blocked/step-up-required) applied before policy evaluation (deny-by-default where configured).

#### A) Authentication requirements
- ParcelIQ MUST accept `Authorization: Bearer <token>` where the token is issued by Sentinel.
- ParcelIQ MUST support both:
  - **User tokens** for interactive experiences (dashboard/admin UI).
  - **Service tokens / API keys** for programmatic integrations (marketplaces, OMS/WMS, shipping automation).
- Tokens MUST be revocable (e.g., session invalidation / refresh token revocation) and MUST have configurable TTLs.

#### B) Authorization requirements (Cedar + `/authorize`)
- For every request that reads or mutates tenant data, ParcelIQ MUST compute:
  - `principal` (user or service principal)
  - `action` (stable action id)
  - `resource` (Cedar `EntityUid`, e.g., `Shipment::"shp_123"`)
  - `context` (service name, correlation id, request metadata, and business parameters needed for ABAC)
- ParcelIQ MUST call Sentinel `POST /v1/authorize` (or equivalent embedded PEP), and MUST enforce:
  - **DENY-by-default** on Sentinel unavailability/timeouts for protected actions.
  - **Fail-closed** on unmapped operations or missing resource-id extraction (see Resource Registry below).
  - Consistent mapping of HTTP routes → `(action, resource_type, id extraction)`.

#### C) Resource Registry mapping (Sentinel `resources/` integration)
ParcelIQ MUST define and maintain Sentinel Resource Registry mappings for all externally exposed API operations, at:
- `sentinel/resources/services/parceliq-api.yaml` (or equivalent service name)

Requirements:
- Every externally reachable route/operation MUST have a mapping.
- On startup, ParcelIQ MUST validate mappings and MUST refuse to start (or deny all) if any protected operation is unmapped.
- Extraction MUST use Sentinel’s supported extractors (`path`, `query`, `header`, `json_body`, `constant`, or `custom` with a provided resolver).
- If the mapping exists but extraction fails at runtime, ParcelIQ MUST treat the request as **not authorized** (fail closed).

#### D) Default permission model (minimum required roles)
ParcelIQ MUST ship with a default tenant-scoped role model (implemented as Cedar entities/edges + policies), at minimum:
- **Owner**: full access including billing, carrier credentials, and security administration.
- **Admin**: manage users/roles, carrier accounts, routing policies, virtual services, webhooks.
- **Shipping Operator**: create/rate/purchase/void/track shipments, manage batches/manifests/pickups.
- **Billing Operator**: invoices, ledger, reconciliation, claims outcomes/adjustments.
- **Developer / Integrator**: manage API keys, webhooks, and view logs/audit for integrations.
- **Read-only**: view-only access for reporting and audit.

Policies MUST be expressed in Cedar and promoted via an auditable workflow.

#### E) Audit and security event emission (Sentinel pipeline)
ParcelIQ MUST emit (directly or via Sentinel `/v1/events`) structured security-relevant events, including:
- Authentication events (login, logout, token refresh failures)
- Authorization outcomes (allow/deny with `deny_reason` / `error_code`)
- High-risk business actions (label purchases, refunds/voids, reroutes/redirects, carrier credential changes, billing adjustments, API key creation/rotation)

Events MUST include `request_id` / `correlation_id`, tenant id, principal id, and the affected resource ids.


### 2.2 Core Endpoints / Capabilities (Expanded)
ParcelIQ MUST provide the following operations in a carrier-agnostic manner. Where a carrier does not support a capability, ParcelIQ MUST return a clear `unsupported_feature` error code and (where possible) guidance on alternatives.

#### A) Address Management + Verification
- Create / retrieve / list address objects.
- Verify addresses (deliverability-oriented checks when available) and return normalized/corrected components plus verification results.
- Support batch address verification.

#### B) Parcel (Package) Modeling
- Create/retrieve parcel objects with weight and (recommended) dimensions and/or predefined package types for accurate rating.
- Support carrier-specific packaging types where applicable (e.g., “flat rate envelope”) and validate constraints.

#### C) International Shipping Data (Customs + Tax IDs)
- Support customs data objects and workflows:
  - Customs information and customs items required to generate carrier customs forms for international shipments.
  - Harmonized codes, country of origin, item value/currency, quantities, and descriptions with validation rules.
- Support tax identifiers on shipments (where required) with validation and carrier compatibility handling (e.g., VAT/EORI/IOSS-like identifiers depending on destination rules).

#### D) Rating (Cost + Delivery Estimates)
- Retrieve rates for a shipment (or order) across eligible carriers/accounts/services.
- Return:
  - Total cost and currency
  - Delivery estimates (delivery days / estimated delivery where supported)
  - Full breakdown (base + surcharges + options)
  - Billable weight details (actual, dimensional, selected)
- Support “advanced” delivery predictions (e.g., time-in-transit distributions) when the underlying carrier and data sources support it.

#### E) Shipment Creation + Label Purchase
- Create shipments from addresses + parcel + options; optionally compute rates at creation time.
- Purchase labels from a chosen rate/service.
- Output MUST include:
  - Shipment ID
  - Tracking number/code
  - Label file links/data (e.g., PDF/ZPL/PNG as available)
  - Selected carrier/service metadata
  - Final price and pricing breakdown

#### F) Refunds and Voids (Post-Purchase Reversal)
- Support void/cancel flows where a label can be voided under carrier rules (void windows, eligibility checks).
- Support refund request tracking where carriers support post-purchase refunds:
  - Status (submitted/refunded/rejected/not_applicable)
  - Carrier reference identifiers

#### G) Returns / Return Labels
- Support return label creation, including:
  - Create return for an existing shipment (where possible)
  - Standalone return label creation
  - Carrier-specific return billing behaviors (bill sender/receiver/third party, where supported)

#### H) Tracking (Trackers) + Updates
- Create/retrieve trackers; trackers may be auto-created from purchased shipments and also created for labels generated outside the system.
- Trackers MUST update over time and expose full event history + current status.
- Support push updates via webhooks and polling fallback.
- Preserve raw carrier events for audit and debugging.

#### I) Pickups (Schedule / Rate / Cancel)
- Schedule carrier pickups tied to shipment(s), retrieve available pickup rates/options for a time window, and cancel pickups when supported.

#### J) ScanForms / Manifests (End-of-Day Handoff)
- Create and retrieve ScanForms / manifests that consolidate shipments for carrier acceptance (including scannable forms where supported).
- Support association of shipments to a manifest and post-creation retrieval.

#### K) Batches (Bulk Operations)
- Support batch objects to operate on many shipments at once, including (at minimum):
  - Batch label purchase
  - Batch pickup scheduling
  - Batch ScanForm creation
  - Consolidated label retrieval (where applicable)
- Batch operations MUST be asynchronous with webhook completion events and status tracking.

#### L) Multi-Parcel “Order” Abstraction
- Provide an order-like object representing a collection of shipments for multi-parcel workflows (create, rate, buy), where supported by underlying carriers or via ParcelIQ abstraction.

#### M) Insurance + Claims
- Support insurance purchase/registration for shipments where available.
- Provide a claims API workflow for insured shipments (lost/damaged/stolen), including status tracking and required documentation hooks.

#### N) Carrier Capability Discovery (Metadata)
- Provide a capability/metadata endpoint that returns per-carrier details useful for onboarding and routing:
  - Service levels, predefined packages, shipment options, supported label formats, and supported features.
- Provide carrier-account credential schema discovery for programmatic onboarding (required fields, validation requirements, test-connection behavior).

#### O) Reporting / Exports
- Provide report generation over time windows (CSV/JSON) for objects such as shipments, trackers, refunds, pickups, manifests, and other activity—suitable for audit/reconciliation pipelines.

#### P) “Ship on Behalf of” Support (Optional / Configurable)
- Support an “end shipper” / ship-on-behalf pattern for platforms that purchase postage for sub-entities while asserting the responsible party details, where carrier rules permit.

---

## 3) Carrier Account Management (Multi-Account, Unlimited)

### 3.1 Account Linking
- A single ParcelIQ user account MUST be able to add:
  - Multiple carriers simultaneously
  - Unlimited carrier accounts (including multiple accounts for the same carrier)
- Each carrier account MUST support:
  - Credential storage (encrypted at rest)
  - Connection verification (“test credentials”)
  - Enable/disable status
  - Metadata fields: nickname, billing profile, warehouse association, default flags

### 3.2 Account Selection Rules
ParcelIQ MUST allow selecting which carrier account is used when:
- Rating shipments
- Purchasing labels
- Running reconciliation
- Filing claims

Selection MUST support:
- Explicit `carrier_account_id` in requests
- Default account per carrier
- Automatic account selection by routing policy (virtual services)

---

## 4) Rating & Pricing Engine (Published + Account-Level Rate Adjustments)
ParcelIQ MUST implement a pricing engine that:
- Understands each supported carrier’s rating logic (zones, weight breaks, dimensional weight, surcharge rules).
- Stores and applies published rate tables by effective date ranges.
- Correctly handles peak-time and complex surcharges with explicit rule modeling.

### 4.1 Published Rates
ParcelIQ MUST store:
- Base rates by service, zone, weight/dim bands, and effective period
- Surcharge schedules (fuel, peak, DAS, residential, oversize, etc.) by effective period
- Rules for:
  - Billable weight (actual vs dimensional vs minimums)
  - Rounding methods (e.g., next whole pound)
  - Package types and constraints

### 4.2 Account-Level Rate Adjustments (User-Entered)
Users MUST be able to define account-level pricing adjustments with:
- **Scope** (can be partial/incomplete):
  - carrier account (required)
  - optional: carrier service(s), package type(s), zone(s), weight bands, destination type, surcharge types, etc.
- **Adjustment type**:
  - Absolute dollar adjustment (e.g., “-$1.25 off base” or “+$2.00 surcharge”)
  - Percent adjustment (e.g., “10% off published base”)
- **Effective period**:
  - start datetime (default = now if omitted)
  - end datetime (default = no expiration if omitted)
- **Priority/ordering**:
  - Adjustments MUST be applied cumulatively in the exact order they were created/entered into the system.

### 4.3 Conversion Rule for Absolute Adjustments
ParcelIQ MUST internally normalize absolute-dollar adjustments into percent adjustments relative to the relevant published rate for the applicable effective period.

Minimum requirements for this normalization:
- The system MUST preserve the original input (absolute amount) for audit.
- The system MUST compute and store the normalized percent(s) used at evaluation time.
- If the adjustment scope is broad (e.g., “-$2 off any UPS Ground”), ParcelIQ MUST:
  - Apply conversion per matching published-rate cell (zone/weight band) OR
  - Use a defined reference rate cell (documented) and disclose the approximation in audit output.
- The system MUST record:
  - Published-rate version/date used for conversion
  - Any approximations made due to incomplete scope

### 4.4 Pricing Output & Audit Breakdown
Every rate quote and purchased shipment MUST return a pricing breakdown that includes:
- Published base rate (with published-rate effective date reference)
- Each surcharge item (name, amount, rule/source)
- Each account-level adjustment applied (id, description, computed percent, resulting delta)
- Final total and currency
- A deterministic “pricing hash/version” for audit and reproducibility

---

## 5) Virtual Services (User-Defined) with Full Shipment Functionality
ParcelIQ MUST allow users to create Virtual Services that:
- Have a unique name/identifier (per user account)
- Define a sell price or pricing model (markup/discount, flat price, tiered, etc.)
- Map to one or more underlying candidate carrier services (across one or multiple carriers/accounts)

Virtual Services MUST support the same end-to-end operations as carrier services:
- Rating (show virtual price and optionally underlying cost breakdown)
- Purchase labels (with underlying carrier execution)
- Cancel/void
- Reroute/intercept (if supported by the chosen underlying service)
- Tracking (unified tracking object referencing underlying tracking number)

### 5.1 Pricing for Virtual Services
Virtual service pricing MUST support at least:
- Flat price (fixed)
- Cost-plus (underlying cost + fixed markup or percent markup)
- Discounted cost (underlying cost - percent)
- Tiered rules by weight, zone, destination type, or service class

Pricing MUST be auditable and included in invoice breakdowns.

---

## 6) Routing Policies — Flexible Mapping from Virtual → Underlying Services
ParcelIQ MUST provide a routing-policy framework that is:
- Flexible (supports many strategies)
- Extensible (new strategies without breaking existing policies)
- Understandable (human-readable configuration + explainable decisions)

### 6.1 Proposed Approach: Policy = Candidate Set + Constraints + Scoring + Fallbacks
A routing policy is composed of:

1) **Candidate Set**
- List of eligible underlying services (`carrier_account_id` + `carrier_service_code`)
- Optional dynamic filters (e.g., exclude a carrier during outage)

2) **Eligibility Constraints (Hard Rules)**
- Must meet constraints such as:
  - Delivery date <= X days
  - Must support signature
  - Max cost ceiling
  - Exclude PO boxes
  - International-only or domestic-only
- If no candidates remain, policy MUST:
  - Fail with a clear reason OR
  - Use a defined fallback policy (next best list)

3) **Scoring / Selection Strategy (Soft Rules)**
Support one or more of:
- Lowest cost
- Fastest transit time
- Weighted scoring (e.g., 70% cost, 30% speed)
- Blended cost (e.g., include operational surcharge, risk score, historical on-time performance)
- Percentage splits (traffic shaping):
  - e.g., 80% UPS Ground, 20% FedEx Home, subject to constraints
- Aggregate cost:
  - e.g., cost + expected surcharge risk + claim rate penalty

4) **Tie-breaking**
- Deterministic ordering (e.g., stable sort by service priority list)

5) **Explainability**
- Policy evaluation MUST return:
  - Which candidates were considered/excluded and why
  - Final score calculation for top candidates

### 6.2 Policy Configuration Format
ParcelIQ MUST offer:
- A JSON-based policy definition (machine-configurable)
- An optional UI abstraction (rule builder) that generates the JSON
- Versioning of policies (publish/draft) and ability to roll back

### 6.3 Runtime Behavior
When creating a shipment using a virtual service:
- ParcelIQ MUST rate eligible candidates
- Apply constraints
- Select a winner using scoring
- Purchase with the selected carrier account/service
- Return a single unified shipment response with:
  - `virtual_service_id`
  - selected underlying carrier details
  - pricing breakdown and (optionally) policy decision explanation

---

## 7) Billing: Balance + Optional Credit Limit

### 7.1 Funding and Charging
ParcelIQ MUST support charging/funding a user account (e.g., via payment processor integrations or offline adjustments).
- Maintain an internal ledger for:
  - Deposits/top-ups
  - Shipment charges
  - Refunds (void/cancel)
  - Reconciliation adjustments (carrier over/under)
  - Manual credits/debits
- All monetary movements MUST be atomic and idempotent.

### 7.2 Spend Limits
Each user account MAY have:
- **Balance** (prepaid funds)
- Optional **Credit Limit** (maximum allowed extra spend)

Constraint:
- A shipment purchase MUST be rejected if it would cause:
  - `total_spend > balance + credit_limit`
- This check MUST be enforced transactionally (no race-condition overdrafts).

### 7.3 Billing Events
ParcelIQ MUST create ledger entries on:
- Label purchase (charge)
- Label void accepted (refund)
- Carrier post-bill adjustments (debit/credit)
- Claims outcomes (credit/refund)

---

## 8) Invoicing (Arbitrary Time Period)
ParcelIQ MUST generate invoices for any user-defined period:
- By date range (start/end) using a defined timezone (default: account timezone)
- Output formats:
  - PDF for human-readable invoice
  - CSV/JSON line items for audit/import
- Include:
  - Shipment line items (shipment id, date, service, tracking, base/surcharges, total)
  - Virtual pricing vs underlying cost (if applicable, controllable visibility)
  - Ledger summary (opening balance, deposits, charges, adjustments, closing balance)
  - Taxes/fees if applicable (explicitly configurable)

Invoices MUST be immutable once finalized (support “void & reissue” if corrections needed).

---

## 9) Carrier Invoice Reconciliation + Claims Management

### 9.1 Reconciliation
ParcelIQ MUST reconcile carrier invoices against expected pricing:
- Ingest carrier invoice data (CSV, EDI, API, or manual upload depending on carrier).
- Match invoice line items to ParcelIQ shipments using:
  - tracking number, label id, shipment id, account identifiers, dates
- Compute deltas:
  - expected vs billed
  - categorize reasons (dim weight change, address correction, fuel/peak differences, unknown charge)
- Generate reconciliation reports and ledger adjustments where applicable.

### 9.2 Unknown Shipments & Exceptions
ParcelIQ MUST detect and manage:
- Unknown shipments (present on carrier invoice, not created through ParcelIQ)
- Undelivered shipments (delivered status missing beyond SLA or lost/damaged indicators)
- Incorrectly rated shipments (billed weight/dims differ materially from original request)

### 9.3 Claims Workflow (End-to-End)
ParcelIQ MUST provide a claims module that:
- Creates a claim record with type, carrier account, shipment references, evidence attachments.
- Tracks claim lifecycle states, e.g.:
  - Draft → Submitted → In Review → Info Requested → Resolved (Won/Lost) → Closed
- Supports:
  - Tasking/assignments (owner, due date, notes)
  - Document upload (proof of value, POD, photos, customs docs, etc.)
  - Carrier communications logging (manual or API-based where possible)
  - Reminders/escalations (notifications/webhooks)

Claims MUST be followable “until completion” with full status history and final financial outcome posted to the ledger.

---

## 10) Operational & Non-Functional Requirements

### 10.1 Reliability and Performance
- High availability for rating and label purchase APIs.
- Clearly defined SLAs for:
  - Quote latency
  - Label purchase latency
  - Webhook delivery retries
- **Per-account throughput**: Each user account MUST be able to sustain **tens of requests per second** (steady-state), including mixed read/write operations (e.g., rating + label purchase + tracking reads).
- **Multi-tenant concurrency**: The system MUST handle **concurrent requests from thousands of user accounts** without violating per-user rate policies or causing noisy-neighbor degradation.
- **Throttling behavior**:
  - Throttling MUST be enforced at the **user account** level with **configurable rate limits per user**.
  - When limits are exceeded, the API MUST return a deterministic error response (e.g., HTTP 429) and SHOULD include retry hints (e.g., `Retry-After`).
  - Throttling MUST be applied consistently across all API surfaces (REST, webhooks ingestion endpoints if applicable, and batch submission endpoints).
- Graceful degradation:
  - If one carrier is down, routing policies can exclude it and continue with others.

### 10.2 Security and Compliance
- **Sentinel required**: ParcelIQ MUST integrate with the Sentinel repository for AuthN/AuthZ, auditing, rate limiting, request signing, and security-state enforcement.
- Encrypt credentials and sensitive PII at rest and in transit.
- **AuthN**: Sentinel-issued bearer tokens for users and service principals; token lifetimes, refresh, and revocation MUST be supported.
- **AuthZ (Cedar)**: Fine-grained access control MUST be enforced via Sentinel Cedar policies and `/v1/authorize` checks using `(principal, action, resource, context)`.
- **Fail-closed posture**:
  - If Sentinel authorization cannot be evaluated for a protected action (PDP timeout/unavailable, invalid mapping, missing resource id), ParcelIQ MUST deny the request.
  - If Sentinel security-state indicates `QUARANTINED` or `BLOCKED`, ParcelIQ MUST deny the request regardless of policy.
- **Request signing & replay protection**:
  - Internal service-to-service calls that are security sensitive (including calls to Sentinel `/authorize` in service mode and `/events`) MUST use Sentinel’s request signing scheme and MUST enforce replay protection (nonce + timestamp).
- **Auditing (immutable)**:
  - ParcelIQ MUST produce audit logs for all high-risk changes and MUST ensure Sentinel audit events capture: `request_id`, `correlation_id`, principal, tenant, action, resource, decision, and decision metadata when available.
  - Minimum audited actions include:
    - Carrier credential create/update/disable
    - API key/service principal create/rotate/revoke
    - Rate table changes and account-level rate adjustment changes
    - Routing policy and virtual service changes
    - Shipment label purchase, void/refund, reroute/intercept
    - Ledger and invoice adjustments
    - Claims workflow state changes and payouts/credits
- PII handling policies (data minimization, retention rules, export/delete support where applicable).

### 10.3 Observability
- Structured logs with correlation IDs per request/shipment.
- Metrics and dashboards:
  - Purchase success rates by carrier
  - Error rates
  - Average quote times
  - Financial anomaly detection (large deltas, frequent adjustments)
- Alerting on carrier outages and reconciliation anomalies.

### 10.4 Extensibility
- Pluggable carrier connectors:
  - Each carrier integration must implement a standard interface (addresses, rating, labels, voids, tracking, reroute, add-ons, pickups, manifests).
- Versioned published rate tables and routing policies.
- Backward-compatible API versioning.

### 10.5 Data Lifecycle and Archival
- **Bounded growth**: The underlying system MUST NOT grow unbounded in primary (hot) storage.
- **Archival policy**:
  - Completed shipments/orders older than a configurable threshold (default **90 days / 3 months**) MUST be migrated from primary storage to **secondary archival storage**.
  - Migration MUST preserve referential integrity (shipments, labels metadata, tracking history snapshots, billing records, reconciliation artifacts, claim references).
- **Access requirements**:
  - Archived orders MUST remain accessible via the same APIs as active orders.
  - Accessing archived orders MAY incur **temporary additional latency** (e.g., while records are hydrated into an active cache), but MUST remain reliable and auditable.
- **Cache hydration**:
  - When an archived order is requested, the system SHOULD hydrate it into an active “order cache” for a bounded time window to improve subsequent access.
  - The cache MUST be size-bounded and eviction policies MUST be documented.
- **Operational controls**:
  - Provide admin/configuration controls for archival thresholds, migration schedules, and rehydration limits.
  - Provide metrics and alerts for archival backlog, hydration latency, and storage utilization.

### 10.6 Sentinel Repository Adoption and Integration Requirements

ParcelIQ MUST adopt the uploaded Sentinel repository as a **required runtime dependency** and MUST NOT re-implement equivalent security functionality in ParcelIQ itself.

#### 10.6.1 Repository usage and packaging
- ParcelIQ MUST consume Sentinel as:
  - A pinned dependency (package + version) **or**
  - A vendored module/submodule with an explicit upgrade process.
- ParcelIQ MUST maintain environment-specific Sentinel inputs alongside the application:
  - `policies/env/<env>/policies/**` (Cedar policies for ParcelIQ)
  - `entities/env/<env>/entities.json` (Cedar entities snapshot inputs or export pipeline)
  - `resources/registry.yaml` and `resources/services/parceliq-api.yaml` (resource + action registry and operation mappings)

#### 10.6.2 Required Sentinel capabilities to use
ParcelIQ MUST use the following Sentinel-provided capabilities:

1) **AuthN (OIDC login)**
- Any ParcelIQ UI (admin console, billing console, ops console) MUST use Sentinel’s OIDC login flow (`/v1/auth/login/*` and `/v1/auth/callback/*`).
- ParcelIQ MUST treat Sentinel as the issuer of tokens and the source of stable internal user ids.

2) **Token service**
- ParcelIQ MUST use Sentinel’s token service (`POST /v1/token`) for:
  - User token issuance/refresh
  - Service principal token issuance (client credentials) for integrations
- ParcelIQ MUST support service principal lifecycle: create, rotate, revoke (backed by Sentinel storage).

3) **Authorization (Cedar via `/v1/authorize`)**
- All ParcelIQ protected operations MUST be mapped to Sentinel actions and resources.
- ParcelIQ MUST include sufficient ABAC context for policies, including at minimum:
  - `service_name`, `correlation_id`
  - request metadata (ip, user_agent when available)
  - tenant id and relevant business fields (e.g., shipping origin/destination country, declared value, carrier, amount)

4) **Resource registry “match → extract → authorize” workflow**
- ParcelIQ MUST use Sentinel’s resource registry mapping approach so that authorization is consistent and centrally reviewable.
- Unmapped routes MUST fail closed.

5) **Rate limiting**
- ParcelIQ MUST implement rate limiting using Sentinel’s primitives and shared backing store (Redis in production).
- Rate limits MUST be configurable per tenant and per principal, and MUST support burst + sustained rules.

6) **Audit/event pipeline**
- ParcelIQ MUST emit Sentinel-compatible audit events for all AuthN/AuthZ decisions and all high-risk ParcelIQ domain events.
- When Kafka is unavailable, ParcelIQ MUST use a durable fallback (e.g., outbox pattern) consistent with Sentinel patterns.

7) **Security state enforcement**
- ParcelIQ MUST integrate with Sentinel `user_security_state` gating for protected actions:
  - QUARANTINED/BLOCKED ⇒ deny
  - STEP_UP_REQUIRED/PENDING_ADMIN_REVIEW ⇒ deny for protected actions, with explainable error codes
- ParcelIQ MUST expose a user-facing error shape that can surface “account quarantined” or “step-up required” without leaking sensitive detection details.

8) **Admin actions integration**
- ParcelIQ operational tooling MUST integrate with Sentinel admin actions for:
  - Listing/acknowledging alerts
  - Quarantining/unquarantining users (or service principals) where supported
- Admin actions MUST require elevated privileges and SHOULD require step-up/MFA or break-glass.

#### 10.6.3 ParcelIQ authorization model (resources + actions)
ParcelIQ MUST define a stable set of Sentinel resource types and actions. Minimum required resource types include:
- `Tenant`, `User`, `Service` (service principal / API key)
- `CarrierAccount`, `CarrierCredential`
- `Shipment`, `RateQuote`, `Label`, `Tracker`, `Batch`, `Manifest`, `Pickup`
- `VirtualService`, `RoutingPolicy`
- `Invoice`, `LedgerEntry`, `ReconciliationRun`, `Claim`
- `WebhookEndpoint`, `ReportExport`

Minimum required action families include:
- Read/list: `read`, `list`, `export`
- Shipping: `create_shipment`, `rate_shipment`, `purchase_label`, `void_label`, `reroute_shipment`, `create_return`, `schedule_pickup`, `create_manifest`, `batch_purchase`
- Billing: `manage_billing`, `create_invoice`, `adjust_ledger`, `run_reconciliation`
- Admin/security: `manage_users`, `manage_roles`, `manage_api_keys`, `manage_carriers`, `manage_policies`

#### 10.6.4 Migration and compatibility
- Existing ParcelIQ API key patterns (if any) MUST be migrated to Sentinel-backed service principals without breaking external integrations.
- ParcelIQ MUST provide an explicit migration plan and tooling for rotating keys/tokens with minimal downtime.


---

## 11) Acceptance Criteria (High-Level)
ParcelIQ is considered compliant with these requirements when:
- A single API client can validate, rate, buy, cancel/void/refund, reroute (where supported), and track shipments across multiple carriers with consistent semantics.
- Users can add unlimited carrier accounts and select them explicitly or via policies.
- Pricing is reproducible and fully auditable (published rates + ordered account adjustments + surcharges/options).
- Virtual services can be created, priced, and fulfilled through flexible routing policies with explainable decisions.
- Billing prevents overspend beyond balance + credit, and invoices can be generated for any period.
- Carrier invoices can be ingested, matched, and reconciled, and claims can be tracked through completion with ledger outcomes.
- Sentinel is integrated end-to-end: all protected operations are authorized via Sentinel/Cedar with fail-closed behavior, and security/audit events are emitted with correlation IDs.
