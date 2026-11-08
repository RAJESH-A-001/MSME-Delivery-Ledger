# Database Schema — MSME Delivery & Acceptance Ledger

This document is the canonical design reference for the PostgreSQL database backing the MSME Delivery & Acceptance Ledger platform. The database is hosted on Supabase (PostgreSQL 15+). It covers all tables, columns, constraints, relationships, indexes, and data-type decisions. No SQL is included — this is a design specification.

---

## Overview

The platform is a decentralised supply-chain ledger for Indian MSMEs. It allows businesses to create orders, track deliveries, accept or dispute goods, upload documents, and anchor key events on the Ethereum blockchain. Supabase Auth manages authentication; `auth.users` is an existing system table and is **not** redefined here.

---

## Tables

### 1. `profiles`

Links application-level user data to `auth.users`. Every registered user has exactly one profile row. The `id` mirrors the Supabase Auth user ID so joins are free.

| Column | Type | Constraints | Default | Description |
|---|---|---|---|---|
| `id` | `UUID` | PK, FK → `auth.users.id` ON DELETE CASCADE | — | Matches the Supabase Auth user ID exactly |
| `full_name` | `TEXT` | NOT NULL | — | User's display name |
| `phone` | `TEXT` | — | NULL | Optional mobile number |
| `avatar_url` | `TEXT` | — | NULL | URL to profile picture (Supabase Storage or external CDN) |
| `created_at` | `TIMESTAMPTZ` | NOT NULL | `NOW()` | Row creation timestamp |
| `updated_at` | `TIMESTAMPTZ` | NOT NULL | `NOW()` | Last update timestamp (maintained by trigger) |

---

### 2. `businesses`

Represents a registered business entity. A business can act as a buyer, a seller, or both. Each business is owned by one profile but can have multiple members via `business_members`.

| Column | Type | Constraints | Default | Description |
|---|---|---|---|---|
| `id` | `UUID` | PK | `gen_random_uuid()` | Surrogate primary key |
| `owner_id` | `UUID` | NOT NULL, FK → `profiles.id` ON DELETE RESTRICT | — | The profile that registered (owns) this business |
| `name` | `TEXT` | NOT NULL | — | Legal or trading name of the business |
| `gstin` | `VARCHAR(15)` | UNIQUE | NULL | GST Identification Number — fixed 15-character format |
| `pan` | `VARCHAR(10)` | — | NULL | PAN card number — fixed 10-character format |
| `address` | `TEXT` | — | NULL | Street / flat / building address |
| `city` | `TEXT` | — | NULL | City name |
| `state` | `TEXT` | — | NULL | Indian state name |
| `pincode` | `VARCHAR(6)` | — | NULL | Indian 6-digit postal code |
| `business_type` | `TEXT` | — | NULL | Classification, e.g. `manufacturer`, `trader`, `service` |
| `is_verified` | `BOOLEAN` | NOT NULL | `FALSE` | Whether the platform has verified the business documents |
| `created_at` | `TIMESTAMPTZ` | NOT NULL | `NOW()` | Row creation timestamp |
| `updated_at` | `TIMESTAMPTZ` | NOT NULL | `NOW()` | Last update timestamp |

---

### 3. `orders`

The central record of a commercial transaction. An order flows from one business (buyer) to another (seller) and progresses through a defined lifecycle. All monetary totals are stored here; line-level amounts live in `order_items`.

| Column | Type | Constraints | Default | Description |
|---|---|---|---|---|
| `id` | `UUID` | PK | `gen_random_uuid()` | Surrogate primary key |
| `order_number` | `TEXT` | NOT NULL, UNIQUE | — | Human-readable identifier, e.g. `ORD-2024-00001` |
| `buyer_business_id` | `UUID` | NOT NULL, FK → `businesses.id` | — | The purchasing business |
| `seller_business_id` | `UUID` | NOT NULL, FK → `businesses.id` | — | The supplying business |
| `created_by` | `UUID` | NOT NULL, FK → `profiles.id` | — | The user who raised the order |
| `status` | `TEXT` | NOT NULL, CHECK (see below) | `'created'` | Current lifecycle stage of the order |
| `total_amount` | `NUMERIC(15,2)` | NOT NULL | `0` | Sum of all line-item totals (maintained by application) |
| `currency` | `VARCHAR(3)` | NOT NULL | `'INR'` | ISO 4217 currency code |
| `notes` | `TEXT` | — | NULL | Free-text remarks from the order creator |
| `expected_delivery_date` | `DATE` | — | NULL | Target delivery date agreed between parties |
| `created_at` | `TIMESTAMPTZ` | NOT NULL | `NOW()` | Row creation timestamp |
| `updated_at` | `TIMESTAMPTZ` | NOT NULL | `NOW()` | Last update timestamp |

**Status CHECK constraint** — allowed values:
`created`, `confirmed`, `dispatched`, `in_transit`, `delivered`, `accepted`, `partially_accepted`, `rejected`, `disputed`, `completed`

**Self-reference CHECK constraint**: `buyer_business_id <> seller_business_id` — a business cannot place an order with itself.

---

### 4. `order_items`

Individual line items within an order. Each row describes one product or service, its quantity, unit of measure, and unit price. The `total_price` is computed automatically by the database.

| Column | Type | Constraints | Default | Description |
|---|---|---|---|---|
| `id` | `UUID` | PK | `gen_random_uuid()` | Surrogate primary key |
| `order_id` | `UUID` | NOT NULL, FK → `orders.id` ON DELETE CASCADE | — | Parent order |
| `description` | `TEXT` | NOT NULL | — | Name or description of the goods/service |
| `quantity` | `NUMERIC(12,3)` | NOT NULL | — | Ordered quantity (supports fractional units) |
| `unit` | `TEXT` | NOT NULL | — | Unit of measure, e.g. `kg`, `pcs`, `litres`, `metres` |
| `unit_price` | `NUMERIC(15,2)` | NOT NULL | — | Price per unit in the order's currency |
| `total_price` | `NUMERIC(15,2)` | GENERATED ALWAYS AS (`quantity * unit_price`) STORED | — | Line-item total — computed by the database, not writable |
| `hsn_code` | `VARCHAR(8)` | — | NULL | HSN/SAC code for GST classification (up to 8 digits) |
| `created_at` | `TIMESTAMPTZ` | NOT NULL | `NOW()` | Row creation timestamp |

---

### 5. `deliveries`

One or more delivery records per order (one-to-many relationship). Each delivery carries its own `shipment_number`, allowing an order to be fulfilled through multiple partial shipments. Kept as a separate table rather than columns on `orders` to maintain clean separation of concerns — logistics data grows independently of commercial data.

| Column | Type | Constraints | Default | Description |
|---|---|---|---|---|
| `id` | `UUID` | PK | `gen_random_uuid()` | Surrogate primary key |
| `order_id` | `UUID` | NOT NULL, FK → `orders.id` ON DELETE RESTRICT | — | Parent order; multiple deliveries may reference the same order |
| `shipment_number` | `TEXT` | NOT NULL | — | Human-readable shipment identifier, e.g. `SHIP-2024-00001`; unique within an order |
| `tracking_number` | `TEXT` | — | NULL | Carrier-issued tracking or AWB number |
| `carrier_name` | `TEXT` | — | NULL | Logistics company name, e.g. `DTDC`, `Blue Dart` |
| `driver_name` | `TEXT` | — | NULL | Name of the delivery driver or agent |
| `driver_phone` | `TEXT` | — | NULL | Contact number for the driver |
| `vehicle_number` | `TEXT` | — | NULL | Vehicle registration plate |
| `dispatched_at` | `TIMESTAMPTZ` | — | NULL | Timestamp when goods left the seller's premises |
| `estimated_arrival` | `TIMESTAMPTZ` | — | NULL | Expected delivery window |
| `delivered_at` | `TIMESTAMPTZ` | — | NULL | Timestamp when goods physically reached the buyer |
| `delivery_address` | `TEXT` | NOT NULL | — | Full destination address at time of dispatch |
| `created_at` | `TIMESTAMPTZ` | NOT NULL | `NOW()` | Row creation timestamp |
| `updated_at` | `TIMESTAMPTZ` | NOT NULL | `NOW()` | Last update timestamp |

---

### 6. `delivery_events`

An append-only audit log of every status change or milestone in a delivery's lifecycle. Rows are never updated or deleted. This table provides the full timeline view shown to both buyer and seller. Each event is tied to a specific delivery (`delivery_id`), not directly to the order.

| Column | Type | Constraints | Default | Description |
|---|---|---|---|---|
| `id` | `UUID` | PK | `gen_random_uuid()` | Surrogate primary key |
| `delivery_id` | `UUID` | NOT NULL, FK → `deliveries.id` ON DELETE CASCADE | — | The delivery this event belongs to |
| `order_id` | `UUID` | NOT NULL, FK → `orders.id` ON DELETE CASCADE | — | Denormalised parent order for direct querying without joining through deliveries |
| `event_type` | `TEXT` | NOT NULL | — | Milestone label, e.g. `dispatched`, `arrived_at_hub`, `out_for_delivery`, `delivered`, `accepted`, `rejected`, `disputed` |
| `performed_by` | `UUID` | NOT NULL, FK → `profiles.id` | — | The user who recorded this event |
| `location` | `TEXT` | — | NULL | GPS coordinates or place description at time of event |
| `notes` | `TEXT` | — | NULL | Optional free-text comment from the performer |
| `accepted_item_ids` | `UUID[]` | — | NULL | For `accepted`/`partially_accepted` events: ordered item IDs that were accepted |
| `rejected_item_ids` | `UUID[]` | — | NULL | For `rejected`/`partially_accepted` events: ordered item IDs that were rejected |
| `rejection_reasons` | `JSONB` | — | NULL | For `partially_accepted`/`rejected` events: maps `order_item_id` → rejection reason string |
| `occurred_at` | `TIMESTAMPTZ` | NOT NULL | `NOW()` | The real-world time the event occurred |
| `created_at` | `TIMESTAMPTZ` | NOT NULL | `NOW()` | Database insertion time (may differ slightly from `occurred_at`) |

**Append-only enforcement** — `delivery_events` must never be updated or deleted after insertion. A database trigger should reject any `UPDATE` or `DELETE` on this table, preserving it as an immutable delivery audit trail.

---

### 7. `documents`

Stores metadata for every file uploaded to Supabase Storage. The actual binary is in a Storage bucket; this table holds the pointer (`storage_path`), content details, and the SHA-256 hash that is simultaneously anchored on-chain.

| Column | Type | Constraints | Default | Description |
|---|---|---|---|---|
| `id` | `UUID` | PK | `gen_random_uuid()` | Surrogate primary key |
| `order_id` | `UUID` | NOT NULL, FK → `orders.id` ON DELETE CASCADE | — | Order this document belongs to |
| `uploaded_by` | `UUID` | NOT NULL, FK → `profiles.id` | — | User who uploaded the file |
| `document_type` | `TEXT` | NOT NULL | — | Category, e.g. `invoice`, `delivery_proof`, `acceptance_note`, `dispute_evidence` |
| `file_name` | `TEXT` | NOT NULL | — | Original filename as uploaded by the user |
| `storage_path` | `TEXT` | NOT NULL | — | Path inside the Supabase Storage bucket (bucket-relative) |
| `file_size_bytes` | `BIGINT` | — | NULL | File size in bytes; used for quota tracking |
| `mime_type` | `TEXT` | — | NULL | MIME type, e.g. `application/pdf`, `image/jpeg` |
| `sha256_hash` | `TEXT` | NOT NULL | — | SHA-256 hex digest of the file content; computed server-side on upload; the same value is written to the blockchain for tamper-evidence |
| `created_at` | `TIMESTAMPTZ` | NOT NULL | `NOW()` | Upload timestamp |

---

### 8. `disputes`

Records formal dispute cases raised by either party when goods are not accepted as expected. A dispute is linked to a specific order and has its own lifecycle from `open` to `resolved`/`closed`.

| Column | Type | Constraints | Default | Description |
|---|---|---|---|---|
| `id` | `UUID` | PK | `gen_random_uuid()` | Surrogate primary key |
| `order_id` | `UUID` | NOT NULL, FK → `orders.id` ON DELETE RESTRICT | — | The order being disputed |
| `raised_by` | `UUID` | NOT NULL, FK → `profiles.id` ON DELETE RESTRICT | — | The user (typically buyer) who raised the dispute |
| `reason` | `TEXT` | NOT NULL | — | Detailed description of the problem |
| `status` | `TEXT` | NOT NULL, CHECK (see below) | `'open'` | Current stage of the dispute |
| `resolution` | `TEXT` | — | NULL | Summary of how the dispute was resolved |
| `resolved_by` | `UUID` | FK → `profiles.id` ON DELETE SET NULL | NULL | Platform admin or mediator who closed the dispute |
| `raised_at` | `TIMESTAMPTZ` | NOT NULL | `NOW()` | When the dispute was formally raised |
| `resolved_at` | `TIMESTAMPTZ` | — | NULL | When the dispute was closed |
| `created_at` | `TIMESTAMPTZ` | NOT NULL | `NOW()` | Row creation timestamp |
| `updated_at` | `TIMESTAMPTZ` | NOT NULL | `NOW()` | Last update timestamp |

**Status CHECK constraint** — allowed values: `open`, `under_review`, `resolved`, `closed`

---

### 9. `blockchain_transactions`

Records every on-chain event that relates to an application entity. Only lightweight blockchain artefacts (hashes, addresses, event metadata) are stored here — no large binary blobs. The `entity_id` is a polymorphic reference enforced at the application layer.

**Entity type CHECK constraint** — allowed values: `order`, `delivery`, `document`, `dispute`.

**Event name CHECK constraint** — allowed values: `OrderCreated`, `DeliveryDispatched`, `DeliveryDelivered`, `AcceptanceRecorded`, `PartialAcceptanceRecorded`, `DisputeRaised`, `DisputeResolved`.

| Column | Type | Constraints | Default | Description |
|---|---|---|---|---|
| `id` | `UUID` | PK | `gen_random_uuid()` | Surrogate primary key |
| `entity_type` | `TEXT` | NOT NULL, CHECK (`entity_type` IN ('order', 'delivery', 'document', 'dispute')) | — | The table the entity lives in |
| `entity_id` | `UUID` | NOT NULL | — | The UUID of the referenced row (polymorphic; no DB-level FK) |
| `tx_hash` | `VARCHAR(66)` | NOT NULL, UNIQUE | — | Ethereum transaction hash — `0x` prefix + 64 hex characters |
| `block_number` | `BIGINT` | — | NULL | Block height at which the transaction was mined |
| `contract_address` | `VARCHAR(42)` | — | NULL | Ethereum address of the smart contract (`0x` + 40 hex) |
| `event_name` | `TEXT` | NOT NULL, CHECK (`event_name` IN ('OrderCreated', 'DeliveryDispatched', 'DeliveryDelivered', 'AcceptanceRecorded', 'PartialAcceptanceRecorded', 'DisputeRaised', 'DisputeResolved')) | — | Solidity event name emitted |
| `event_data` | `JSONB` | — | NULL | Decoded event parameters as a JSON object — no large binary fields |
| `network` | `TEXT` | NOT NULL | `'sepolia'` | Ethereum network identifier, e.g. `sepolia`, `mainnet` |
| `confirmed_at` | `TIMESTAMPTZ` | — | NULL | Timestamp when the transaction reached sufficient block confirmations |
| `created_at` | `TIMESTAMPTZ` | NOT NULL | `NOW()` | Row insertion timestamp |

**Append-only enforcement** — `blockchain_transactions` must never be updated or deleted after insertion. A database trigger should reject any `UPDATE` or `DELETE` on this table, preserving it as an immutable on-chain audit trail.

---

### Extra Table: `business_members`

**Justification**: The `businesses` table records a single `owner_id`, but real businesses have multiple employees who must be able to create orders, upload documents, and log delivery events. Without this table, every action would require the business owner to act personally, which is unworkable. `business_members` grants role-based access to any number of profiles for a given business.

| Column | Type | Constraints | Default | Description |
|---|---|---|---|---|
| `id` | `UUID` | PK | `gen_random_uuid()` | Surrogate primary key |
| `business_id` | `UUID` | NOT NULL, FK → `businesses.id` ON DELETE CASCADE | — | The business the member belongs to |
| `profile_id` | `UUID` | NOT NULL, FK → `profiles.id` ON DELETE CASCADE | — | The user being granted membership |
| `role` | `TEXT` | NOT NULL, CHECK (see below) | `'member'` | Permission level within the business |
| `invited_by` | `UUID` | FK → `profiles.id` ON DELETE SET NULL | NULL | The admin or owner who sent the invitation |
| `joined_at` | `TIMESTAMPTZ` | NOT NULL | `NOW()` | When the user accepted the invitation |
| UNIQUE(`business_id`, `profile_id`) | — | — | — | Prevents duplicate membership rows |

**Role CHECK constraint** — allowed values: `owner`, `admin`, `member`

---

## Relationships

The diagram below describes all foreign-key relationships in plain language.

```
auth.users (Supabase Auth)
  └── profiles (1:1 — id mirrors auth.users.id)
        ├── businesses (1:many — owner_id)
        │     └── business_members (many:many bridge between businesses and profiles)
        └── orders (created_by — the initiating user)

businesses
  ├── orders (buyer_business_id — the purchasing side)
  └── orders (seller_business_id — the selling side)

orders
  ├── order_items    (1:many — cascade delete)
  ├── deliveries     (1:many — order_id + shipment_number)
  ├── delivery_events (1:many — cascade delete)
  ├── documents      (1:many — cascade delete)
  └── disputes       (1:many — an order may have multiple dispute rounds)

profiles
  ├── delivery_events.performed_by  (who logged the event)
  ├── documents.uploaded_by         (who uploaded the file)
  ├── disputes.raised_by            (who raised the dispute)
  ├── disputes.resolved_by          (who resolved the dispute)
  └── business_members.invited_by  (who sent the invitation)

blockchain_transactions
  └── polymorphic → orders | deliveries | documents | disputes
      (entity_type + entity_id — enforced at application level, not by DB FK)
```

### Key relationship notes

- **profiles ↔ auth.users**: The cascade delete means deleting a Supabase Auth user automatically removes the profile and, via further cascades, all their business memberships.
- **orders self-check**: An order cannot have the same business on both the buyer and seller side (`CHECK buyer_business_id <> seller_business_id`).
- **orders → order_items / delivery_events / documents**: Cascade delete keeps orphaned line items and event logs from persisting after an order is removed.
- **deliveries → orders**: One order may have many deliveries; each is distinguished by `shipment_number`. No `UNIQUE` constraint on `order_id` — shipments are independent.
- **disputes**: Intentionally **not** cascade-deleted with the order. If the order record is ever removed (edge case), disputes should be reviewed first; application logic must handle this.
- **blockchain_transactions**: The polymorphic `entity_type` + `entity_id` pair points to any of `orders`, `deliveries`, `documents`, or `disputes`. There is no database-level FK because a single FK column cannot reference multiple tables. The application layer is responsible for consistency.

---

## Indexes

Indexes beyond those automatically created for primary keys and UNIQUE constraints.

### `order_items`

| Index | Columns | Type | Justification |
|---|---|---|---|
| `idx_order_items_order_id` | `order_id` | B-tree | Retrieve all line items for a given order |

### `orders`

| Index | Columns | Type | Justification |
|---|---|---|---|
| `idx_orders_buyer_business_id` | `buyer_business_id` | B-tree | Fetch all orders where a business is the buyer |
| `idx_orders_seller_business_id` | `seller_business_id` | B-tree | Fetch all orders where a business is the seller |
| `idx_orders_status` | `status` | B-tree | Filter orders by lifecycle stage |
| `idx_orders_created_at` | `created_at DESC` | B-tree | List recent orders |

### `deliveries`

| Index | Columns | Type | Justification |
|---|---|---|---|
| `idx_deliveries_order_id` | `order_id` | B-tree | Fetch all deliveries for an order |
| `idx_deliveries_shipment_number` | `shipment_number` | B-tree | Look up a delivery by its shipment number |

### `delivery_events`

| Index | Columns | Type | Justification |
|---|---|---|---|
| `idx_delivery_events_delivery_id` | `delivery_id` | B-tree | Fetch all events for a specific delivery |
| `idx_delivery_events_order_id` | `order_id` | B-tree | Retrieve full timeline for an order (denormalised) |
| `idx_delivery_events_occurred_at` | `occurred_at DESC` | B-tree | Chronological event display (most-recent-first) |
| `idx_delivery_events_event_type` | `event_type` | B-tree | Filter timeline by milestone category |

### `documents`

| Index | Columns | Type | Justification |
|---|---|---|---|
| `idx_documents_order_id` | `order_id` | B-tree | Fetch all documents attached to an order |
| `idx_documents_document_type` | `document_type` | B-tree | Filter by document category (e.g. all invoices) |
| `idx_documents_sha256_hash` | `sha256_hash` | B-tree | Verify uniqueness / look up a document by its content hash |

### `disputes`

| Index | Columns | Type | Justification |
|---|---|---|---|
| `idx_disputes_order_id` | `order_id` | B-tree | Fetch all disputes for an order |
| `idx_disputes_status` | `status` | B-tree | Filter active/resolved disputes in admin dashboard |
| `idx_disputes_raised_by` | `raised_by` | B-tree | Show all disputes raised by a specific user |

### `blockchain_transactions`

| Index | Columns | Type | Justification |
|---|---|---|---|
| `idx_blockchain_entity` | `(entity_type, entity_id)` | B-tree (composite) | Look up all on-chain records for a specific application entity |
| `idx_blockchain_confirmed_at` | `confirmed_at DESC` | B-tree | Query recently confirmed transactions; NULL rows (unconfirmed) sort last |

The `UNIQUE(tx_hash)` constraint already creates an index on transaction hash lookup.

### `business_members`

| Index | Columns | Type | Justification |
|---|---|---|---|
| `idx_business_members_business_id` | `business_id` | B-tree | List all members of a business |

The `UNIQUE(business_id, profile_id)` constraint already creates a composite index covering profile-side lookups.

---

## Data Types Rationale

### `UUID` for all primary keys
UUIDs are generated client-side or by `gen_random_uuid()` without coordination. This avoids sequential integer predictability, supports offline order drafting, and aligns with Supabase Auth's own `UUID` user IDs.

### `NUMERIC(15,2)` for monetary amounts
`NUMERIC` is exact (no floating-point rounding), which is critical for financial values. The precision `(15,2)` supports Indian Rupee amounts up to ₹999,999,999,999.99 — sufficient for large MSME transactions — with two decimal places for paise.

### `NUMERIC(12,3)` for quantities
Three decimal places cover common physical measurement units (e.g. 10.500 kg, 2.250 litres) without floating-point imprecision.

### `TIMESTAMPTZ` for all timestamps
`TIMESTAMPTZ` stores UTC internally and converts to the session time zone on retrieval. This is essential for a platform where businesses may be queried from different time zones, and for unambiguous blockchain event correlation.

### `TEXT` for variable-length strings
PostgreSQL stores `TEXT` and `VARCHAR` identically on disk. `TEXT` is preferred for all columns without a meaningful hard upper limit (names, addresses, descriptions, notes, paths). `VARCHAR(n)` is used only where a business or regulatory constraint defines a maximum length: `gstin VARCHAR(15)`, `pan VARCHAR(10)`, `pincode VARCHAR(6)`, `currency VARCHAR(3)`, `hsn_code VARCHAR(8)`, `tx_hash VARCHAR(66)`, `contract_address VARCHAR(42)`.

### `BIGINT` for `file_size_bytes` and `block_number`
`file_size_bytes` can exceed 2 GB for large archive files, so `BIGINT` avoids overflow. Ethereum block numbers are already in the hundreds of millions and will grow indefinitely; `BIGINT` (up to ~9.2 × 10¹⁸) is comfortably future-proof.

### `JSONB` for `blockchain_transactions.event_data`
Decoded Solidity event parameters are inherently schema-variable — each event name has different fields. `JSONB` stores them efficiently in a binary-indexed format, supports GIN indexing if needed, and allows partial extraction without deserialising the entire payload. No large binary blobs are permitted in this column; those live in Supabase Storage.

### `BOOLEAN` for `businesses.is_verified`
A simple two-state flag. If multi-stage verification is required in future, this can be replaced with a `TEXT` status column without breaking existing queries that read `FALSE` as unverified.

### `DATE` for `expected_delivery_date`
Delivery dates are business-day granularity — there is no meaningful sub-day component. `DATE` is more semantically correct than `TIMESTAMPTZ` and prevents accidental time-zone issues when the date crosses midnight.

### Generated column for `order_items.total_price`
`total_price` is always `quantity * unit_price`. Making it a `GENERATED ALWAYS AS … STORED` column eliminates an entire class of data-consistency bugs where the application could write a stale or incorrect total. The database guarantees correctness automatically.
