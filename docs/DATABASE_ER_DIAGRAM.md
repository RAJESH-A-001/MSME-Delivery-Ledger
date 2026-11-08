# Database ER Diagram

This diagram illustrates the full entity-relationship model for the MSME Delivery & Acceptance Ledger, backed by PostgreSQL via Supabase. It covers all tables — from authentication and business profiles through orders, deliveries, documents, disputes, and on-chain audit records — along with their primary keys, foreign keys, and cardinality relationships.

```mermaid
erDiagram
    AUTH_USERS {
        uuid id
    }

    PROFILES {
        uuid id
        string full_name
        string phone
        string avatar_url
        timestamp created_at
        timestamp updated_at
    }

    BUSINESSES {
        uuid id
        uuid owner_id
        string name
        string gstin
        string pan
        string address
        string city
        string state
        string pincode
        string business_type
        boolean is_verified
        timestamp created_at
        timestamp updated_at
    }

    BUSINESS_MEMBERS {
        uuid id
        uuid business_id
        uuid profile_id
        string role
        uuid invited_by
        timestamp joined_at
    }

    ORDERS {
        uuid id
        string order_number
        uuid buyer_business_id
        uuid seller_business_id
        uuid created_by
        string status
        numeric total_amount
        string currency
        string notes
        date expected_delivery_date
        timestamp created_at
        timestamp updated_at
    }

    ORDER_ITEMS {
        uuid id
        uuid order_id
        string description
        numeric quantity
        string unit
        numeric unit_price
        numeric total_price
        string hsn_code
        timestamp created_at
    }

    DELIVERIES {
        uuid id
        uuid order_id
        string shipment_number
        string tracking_number
        string carrier_name
        string driver_name
        string driver_phone
        string vehicle_number
        timestamp dispatched_at
        timestamp estimated_arrival
        timestamp delivered_at
        string delivery_address
        timestamp created_at
        timestamp updated_at
    }

    DELIVERY_EVENTS {
        uuid id
        uuid delivery_id
        uuid order_id
        string event_type
        uuid performed_by
        string location
        string notes
        string accepted_item_ids
        string rejected_item_ids
        string rejection_reasons
        timestamp occurred_at
        timestamp created_at
    }

    DOCUMENTS {
        uuid id
        uuid order_id
        uuid uploaded_by
        string document_type
        string file_name
        string storage_path
        integer file_size_bytes
        string mime_type
        string sha256_hash
        timestamp created_at
    }

    DISPUTES {
        uuid id
        uuid order_id
        uuid raised_by
        string reason
        string status
        string resolution
        uuid resolved_by
        timestamp raised_at
        timestamp resolved_at
        timestamp created_at
        timestamp updated_at
    }

    BLOCKCHAIN_TRANSACTIONS {
        uuid id
        string entity_type
        uuid entity_id
        string tx_hash
        bigint block_number
        string contract_address
        string event_name
        jsonb event_data
        string network
        timestamp confirmed_at
        timestamp created_at
    }

    AUTH_USERS ||--|| PROFILES : "authenticates as"
    PROFILES ||--o{ BUSINESSES : "owns"
    PROFILES ||--o{ BUSINESS_MEMBERS : "is member via"
    PROFILES ||--o{ BUSINESS_MEMBERS : "invited member via"
    BUSINESSES ||--o{ BUSINESS_MEMBERS : "has members"
    BUSINESSES ||--o{ ORDERS : "places as buyer"
    BUSINESSES ||--o{ ORDERS : "fulfils as seller"
    PROFILES ||--o{ ORDERS : "created by"
    ORDERS ||--o{ ORDER_ITEMS : "contains"
    ORDERS ||--o{ DELIVERIES : "has deliveries"
    DELIVERIES ||--o{ DELIVERY_EVENTS : "has events"
    PROFILES ||--o{ DELIVERY_EVENTS : "performed by"
    ORDERS ||--o{ DOCUMENTS : "has documents"
    PROFILES ||--o{ DOCUMENTS : "uploaded by"
    ORDERS ||--o{ DISPUTES : "subject of"
    PROFILES ||--o{ DISPUTES : "raised by"
    PROFILES ||--o{ DISPUTES : "resolved by"
    BLOCKCHAIN_TRANSACTIONS }o--|| ORDERS : "anchors order events"
    BLOCKCHAIN_TRANSACTIONS }o--|| DELIVERIES : "anchors delivery events"
    BLOCKCHAIN_TRANSACTIONS }o--|| DOCUMENTS : "anchors document events"
    BLOCKCHAIN_TRANSACTIONS }o--|| DISPUTES : "anchors dispute events"
```

---

## Relationship Legend

| Notation | Meaning |
|---|---|
| `\|\|--\|\|` | **One-to-one** — exactly one record on each side (e.g., one Order has exactly one Delivery) |
| `\|\|--o{` | **One-to-many** — one record on the left, zero or more on the right (e.g., one Business has many Orders) |
| `}o--\|\|` | **Many-to-one** — many records on the left reference one on the right (inverse of one-to-many) |

> Crow's foot notation: `|` = exactly one, `o` = zero or one, `{` / `}` = many (zero or more).

---

## Key Design Notes

- **UUID primary keys everywhere** — all tables use `uuid` PKs generated server-side, which is Supabase-idiomatic and avoids sequential-ID enumeration attacks.
- **`auth.users` ↔ `profiles` separation** — authentication identity lives in Supabase Auth (`auth.users`); application-level profile data (name, phone, avatar) lives in a separate `profiles` table linked 1-to-1, keeping auth concerns isolated from business logic.
- **Multi-tenancy via `businesses` + `business_members`** — a single user profile can belong to multiple businesses with different roles; a `UNIQUE(business_id, profile_id)` constraint prevents duplicate membership rows.
- **Buyer/seller duality on `orders`** — the `orders` table holds two FK references to `businesses` (`buyer_business_id` and `seller_business_id`), allowing both parties to be first-class entities without duplicating the order model.
- **`order_items.total_price` is a generated column** — computed as `quantity × unit_price` by the database, eliminating the risk of application-layer calculation drift.
- **`deliveries` is one-to-many with `orders`** (each shipment distinguished by `shipment_number`) while `delivery_events` is one-to-many with `deliveries`, cleanly separating the static delivery record from its audit-trail of location/status events.
- **Cascade deletes on child tables** — `order_items`, `delivery_events`, and `documents` all declare `ON DELETE CASCADE` from `orders`, ensuring no orphan rows when an order is removed; `deliveries` and `disputes` do not cascade, preserving forensic data.
- **Polymorphic `blockchain_transactions`** — the `entity_type` + `entity_id` pair provides a schema-agnostic way to anchor an on-chain transaction to any domain entity (order, delivery, document, etc.) without requiring per-entity FK columns or separate junction tables.
