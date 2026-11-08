# Database Workflows

This document describes the end-to-end database workflows for the MSME Delivery & Acceptance Ledger platform. It covers how records are created, updated, and linked across the `orders`, `order_items`, `deliveries`, `delivery_events`, `documents`, `disputes`, and `blockchain_transactions` tables as business events occur. All critical state transitions are enforced at the application layer and anchored on the Ethereum blockchain for tamper-evident audit trails.

---

## 1. Order Lifecycle

### Order Statuses

| Status | Description | Who Sets It | Trigger |
|---|---|---|---|
| `created` | Buyer has placed the order; awaiting seller acknowledgement | Buyer member | Manual action |
| `confirmed` | Seller has acknowledged and accepted the order | Seller member | Manual action |
| `dispatched` | Goods have been handed over to the carrier | Seller member | Manual action; also creates a `deliveries` record |
| `in_transit` | Carrier has confirmed the shipment is moving | System / Seller | Delivery tracking event |
| `delivered` | Goods have reached the destination address | Seller / Carrier / System | Delivery event (type: `delivered`) |
| `accepted` | Buyer confirms all goods are received in acceptable condition | Buyer member | Manual action |
| `partially_accepted` | Buyer accepts some items and rejects others | Buyer member | Manual action |
| `rejected` | Buyer rejects the entire delivery | Buyer member | Manual action |
| `disputed` | A formal dispute has been raised by either party | Buyer or Seller | Dispute record created |
| `completed` | Order is fully settled — payment confirmed, all actions finalised | System / Admin | Final state; triggered after acceptance or resolution |

---

### Valid Status Transitions

| From Status | To Status | Authorised By | Condition |
|---|---|---|---|
| `created` | `confirmed` | Seller | Seller reviews and accepts the order |
| `created` | `rejected` | Seller | Seller declines the order |
| `confirmed` | `dispatched` | Seller | Goods handed to carrier; `deliveries` row created |
| `dispatched` | `in_transit` | Seller / System | Carrier pickup event received |
| `in_transit` | `delivered` | Seller / System / Carrier | Delivery event of type `delivered` recorded |
| `delivered` | `accepted` | Buyer | Buyer confirms all items are OK |
| `delivered` | `partially_accepted` | Buyer | Buyer specifies accepted and rejected items |
| `delivered` | `rejected` | Buyer | Buyer rejects the entire delivery |
| `delivered` | `disputed` | Buyer or Seller | Either party raises a formal dispute |
| `accepted` | `completed` | System | Payment confirmation received |
| `partially_accepted` | `completed` | System | Partial settlement confirmed |
| `partially_accepted` | `disputed` | Buyer or Seller | Either party escalates the partial outcome |
| `rejected` | `disputed` | Seller | Seller challenges the buyer's rejection |
| `disputed` | `accepted` | Admin / Resolution | Dispute resolved in buyer's favour (full acceptance) |
| `disputed` | `rejected` | Admin / Resolution | Dispute resolved — rejection upheld |
| `disputed` | `partially_accepted` | Admin / Resolution | Dispute resolved with partial outcome |
| `disputed` | `completed` | Admin / Resolution | Dispute resolved and order directly settled |

> [!IMPORTANT]
> Any transition not listed above is **not permitted**. The application layer must validate every status change against this graph before persisting it. Disputed orders **cannot** be moved directly to `completed` without passing through a resolution step.

---

### Order Creation Flow

1. **Buyer submits the order** — the application validates that the buyer's business ID ≠ the seller's business ID (self-orders are forbidden).
2. **Insert `orders` row** — a new row is created with `status = 'created'`, `buyer_id`, `seller_id`, `created_at`, and the computed `total_amount`.
3. **Insert `order_items` rows** — one row per line item, each with `product_id`, `quantity`, `unit_price`, and `total_price`. The sum of all `total_price` values must equal `orders.total_amount`.
4. **Blockchain anchoring** — the backend computes a hash of the order payload, broadcasts an `OrderCreated` event to the Ethereum contract, waits for confirmation, then inserts a `blockchain_transactions` row recording the `tx_hash`, `block_number`, and `event_type = 'OrderCreated'` linked to the new `order_id`.

---

### Order Confirmation Flow

1. **Seller calls the confirm endpoint** — the application verifies the requesting user belongs to the seller business.
2. **Validate transition** — `created → confirmed` is checked against the allowed transition graph.
3. **Update `orders` row** — `status` is set to `'confirmed'`, `updated_at` is refreshed.
4. **Blockchain anchoring** — an `OrderConfirmed` event is broadcast; the resulting `tx_hash` and `block_number` are written to `blockchain_transactions`.

---

## 2. Delivery Lifecycle

### Delivery Record Creation

When an order transitions from `confirmed` to `dispatched`:

1. **Update `orders.status`** to `'dispatched'`.
2. **Insert `deliveries` row** — captures `order_id`, `carrier_name`, `tracking_number`, `dispatched_at`, and initial `expected_delivery_date`.
3. **Insert first `delivery_events` row** — `event_type = 'dispatched'`, `recorded_by`, `occurred_at`, and any carrier reference notes. This row is **append-only** and must never be updated or deleted after creation.
4. **Blockchain anchoring** — a `DeliveryDispatched` event is recorded in `blockchain_transactions`.

---

### Delivery Events

The `delivery_events` table is an **immutable append-only log**. Every state change in the physical journey appends a new row.

| Event Type | Description | Who Records | Linked Order Status |
|---|---|---|---|
| `dispatched` | Goods handed to carrier at origin | Seller | `dispatched` |
| `picked_up` | Carrier collects the shipment | Carrier / System | `in_transit` |
| `arrived_at_hub` | Shipment reaches a transit hub | Carrier / System | `in_transit` |
| `out_for_delivery` | Shipment is on the last-mile vehicle | Carrier / System | `in_transit` |
| `delivery_attempted` | Delivery tried but failed (no one present etc.) | Carrier / System | `in_transit` |
| `delivered` | Goods successfully handed over at destination | Carrier / System / Seller | `delivered` |
| `returned` | Goods returned to sender after failed delivery | Carrier / System | `rejected` |

---

### Delivery Completion

When a `delivered` delivery event is recorded:

1. **Append `delivery_events` row** with `event_type = 'delivered'` and `occurred_at` timestamp.
2. **Update `orders.status`** to `'delivered'` and refresh `orders.updated_at`.
3. **Update `deliveries.actual_delivery_date`** with the event's `occurred_at` value.
4. The order now awaits a buyer action (acceptance, partial acceptance, rejection, or dispute).

---

## 3. Acceptance Workflow

### Full Acceptance

1. Buyer reviews all items and confirms they are in acceptable condition.
2. **Update `orders.status`** to `'accepted'`.
3. **Append `delivery_events` row** linked to the relevant `delivery_id`, with `event_type = 'accepted'`, `performed_by = buyer_user_id`, `accepted_item_ids` listing all accepted item IDs, notes, and timestamp.
4. **Blockchain anchoring** — an `AcceptanceRecorded` event is broadcast and recorded in `blockchain_transactions`, including the hash of the acceptance document if one was uploaded.
5. The system subsequently moves the order to `completed` once payment is confirmed.

---

### Partial Acceptance

1. Buyer specifies which items are accepted (by `order_item_id`) and which are rejected, along with reasons.
2. **Update `orders.status`** to `'partially_accepted'`.
3. **Append `delivery_events` row** linked to the relevant `delivery_id`, populating `accepted_item_ids`, `rejected_item_ids`, and `rejection_reasons` (JSONB mapping `order_item_id` → reason) columns with the structured acceptance data.
4. **Blockchain anchoring** — a `PartialAcceptanceRecorded` event is written to `blockchain_transactions`.
5. Either party may subsequently raise a dispute, or the system settles the partial outcome and transitions to `completed`.

---

### Rejection

1. Buyer rejects the entire delivery and provides a reason.
2. **Update `orders.status`** to `'rejected'`.
3. **Append `delivery_events` row** linked to the relevant `delivery_id`, with `event_type = 'rejected'`, `rejected_item_ids` listing all item IDs, the rejection reason, and timestamp.
4. The seller may challenge this by raising a dispute (transition: `rejected → disputed`).

---

### Acceptance Evidence

1. Buyer (or seller) uploads an acceptance note or delivery receipt via the documents endpoint.
2. The backend computes the **SHA-256 hash of the file server-side** before inserting the `documents` row. The `sha256_hash` field is non-nullable and must be set on insert.
3. The `documents` row is linked to the `order_id` with `document_type = 'acceptance_note'`.
4. The same SHA-256 hash is passed as calldata when the `AcceptanceRecorded` on-chain event is broadcast, anchoring the hash immutably to the Ethereum transaction.
5. To verify document authenticity at any later date: recompute the SHA-256 of the stored file and compare it to the value on-chain. A mismatch indicates tampering.

---

## 4. Dispute Workflow

### Raising a Dispute

1. Either the buyer or the seller calls the **raise dispute** endpoint, providing a reason and optional initial evidence.
2. **Insert `disputes` row** — `order_id`, `raised_by`, `reason`, `status = 'open'`, `created_at`.
3. **Update `orders.status`** to `'disputed'`.
4. **Append `delivery_events` row** linked to the relevant `delivery_id`, with `event_type = 'disputed'` and a reference to the new `dispute_id` in `notes`.
5. **Notifications sent** to both parties (buyer and seller) via the platform notification system.
6. Both parties are prompted to upload `dispute_evidence` documents (linked in the `documents` table with `document_type = 'dispute_evidence'`).
7. **Blockchain anchoring** — a `DisputeRaised` event is broadcast and recorded in `blockchain_transactions`.

---

### Dispute Statuses

| Status | Description | Who Sets It |
|---|---|---|
| `open` | Dispute has been raised; awaiting review | System (on creation) |
| `under_review` | An admin or arbitration process is actively reviewing the dispute | Admin |
| `resolved` | A resolution has been determined and recorded | Admin |
| `closed` | Dispute is fully closed; all downstream order actions completed | System / Admin |

---

### Dispute Resolution

When an admin resolves a dispute:

1. **Update `disputes.status`** to `'resolved'`.
2. **Set `disputes.resolution`** — free-text description of the resolution outcome.
3. **Set `disputes.resolved_by`** — the admin user ID who made the determination.
4. **Set `disputes.resolved_at`** — current UTC timestamp.
5. **Update `orders.status`** to the appropriate outcome: `accepted`, `rejected`, `partially_accepted`, or `completed`.
6. **Append `delivery_events` row** linked to the relevant `delivery_id`, with `event_type = 'dispute_resolved'`, the resolution summary, and timestamp.
7. **Update `disputes.status`** to `'closed'` once all downstream order actions are complete.
8. **Blockchain anchoring** — a `DisputeResolved` event is broadcast; the `tx_hash` and optionally a hash of the resolution document are recorded in `blockchain_transactions`.

---

### Dispute Transition Rules

| From Status | To Status | Authorised By |
|---|---|---|
| `open` | `under_review` | Admin |
| `under_review` | `resolved` | Admin |
| `resolved` | `closed` | System / Admin |

> [!WARNING]
> Skipping states (e.g., `open → closed`) is not permitted. The application must enforce this linear progression.

---

## 5. Blockchain Anchoring

### What Gets Anchored On-Chain

| Event | Supabase Trigger | On-Chain Data | Off-Chain Data (Supabase) |
|---|---|---|---|
| Order created | Buyer places order | `tx_hash`, `OrderCreated` event | Full order details, item quantities, pricing |
| Delivery dispatched | Order moves to `dispatched` | `tx_hash`, `DeliveryDispatched` event | Carrier name, tracking number, expected date |
| Goods delivered | Delivery reaches destination | `tx_hash`, `DeliveryDelivered` event | Delivery timestamp, recipient confirmation |
| Goods accepted | Buyer accepts delivery | `tx_hash`, `AcceptanceRecorded` event, document `sha256_hash` | Acceptance note document, item-level notes |
| Partial acceptance | Buyer accepts some items | `tx_hash`, `PartialAcceptanceRecorded` event | Accepted/rejected item IDs, rejection reasons |
| Dispute raised | Dispute record created | `tx_hash`, `DisputeRaised` event | Dispute reason, evidence documents |
| Dispute resolved | Admin resolves dispute | `tx_hash`, `DisputeResolved` event, resolution hash | Resolution text, resolved_by, resolved_at |

---

### Recording Blockchain Transactions

1. The backend constructs and **broadcasts the transaction** to the Ethereum network via the configured RPC endpoint.
2. The backend **polls or subscribes** for the transaction receipt until the required number of block confirmations is reached.
3. Once confirmed, the backend **inserts a `blockchain_transactions` row** containing:
   - `entity_type` (e.g., `'order'`, `'delivery'`, `'document'`, `'dispute'`) and `entity_id` (the UUID of the referenced row)
   - `event_name` (e.g., `'OrderCreated'`, `'AcceptanceRecorded'`, `'PartialAcceptanceRecorded'`)
   - `tx_hash` — the confirmed Ethereum transaction hash
   - `block_number` — the block in which the transaction was mined
   - `created_at` — UTC timestamp of insertion
4. This row is **append-only** — it must never be updated or deleted.

---

### Off-Chain / On-Chain Relationship

The platform uses a **hybrid data architecture** where Supabase and the Ethereum blockchain serve complementary roles:

| Concern | Supabase (Off-Chain) | Ethereum (On-Chain) |
|---|---|---|
| **Storage** | Full structured data — orders, items, documents, quantities, prices | Hashes and event proofs only (calldata) |
| **Purpose** | Operational queries, reporting, UI data source | Tamper-evident audit log |
| **Mutability** | Mutable (with controlled transitions) | Immutable once confirmed |
| **Verification** | Source of truth for business logic | Source of truth for integrity proofs |

**Verification protocol:**
- Retrieve the document or order record from Supabase.
- Recompute its SHA-256 hash locally.
- Look up the corresponding `blockchain_transactions` row and fetch the on-chain event's calldata hash.
- If the two hashes **match** → the data is authentic and unaltered.
- If the two hashes **differ** → the off-chain data has been tampered with; the discrepancy must be investigated.

Neither side alone is sufficient: Supabase provides the data, the blockchain provides the proof. Both must agree for a record to be considered trustworthy.

---

## 6. Data Integrity Rules

The following business rules are enforced at the **application layer** (FastAPI) and, where possible, additionally at the **database constraint level** (Supabase/PostgreSQL):

1. **No self-orders** — the `buyer_id` on an `orders` row must never equal the `seller_id`. An order placed between the same business entity is rejected at creation time.

2. **Order total consistency** — `orders.total_amount` must equal the sum of `order_items.total_price` for all items belonging to that order. Any mismatch causes the creation request to be rejected.

3. **`delivery_events` is append-only** — rows in this table must never be updated or deleted after insertion. It is a permanent, chronological audit log of all delivery and acceptance events.

4. **`blockchain_transactions` is append-only** — rows must never be updated or deleted. Each row is a permanent record of an on-chain event.

5. **Server-side hash computation** — the `sha256_hash` field on a `documents` row must be computed by the backend from the actual file bytes before the row is inserted. Clients must never supply this value directly; it is always derived server-side.

6. **Allowed transition graph enforcement** — every status change on an `orders` row must be validated against the [Valid Status Transitions](#valid-status-transitions) table before the update is applied. Transitions not listed in the graph are rejected with an error.

7. **No direct `disputed → completed` transition** — a disputed order cannot be moved directly to `completed` by any party. It must pass through a formal dispute resolution step (resulting in `accepted`, `rejected`, or `partially_accepted`) before the system can move it to `completed`.
