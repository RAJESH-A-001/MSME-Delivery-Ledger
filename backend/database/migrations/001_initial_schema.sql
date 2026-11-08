-- ============================================================================
-- Migration 001: Initial Schema — MSME Delivery & Acceptance Ledger
-- Creates all 10 approved tables with PKs, FKs, CHECK constraints, generated
-- columns, and indexes. Applied in dependency order.
-- ============================================================================

-- Enable pgcrypto for gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- 1. profiles
-- Links application-level user data to auth.users. id mirrors auth.users.id.
-- ---------------------------------------------------------------------------
CREATE TABLE profiles (
    id             UUID        PRIMARY KEY,
    full_name      TEXT        NOT NULL,
    phone          TEXT,
    avatar_url     TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- 2. businesses
-- Represents a registered business entity. Owned by one profile, many members.
-- ---------------------------------------------------------------------------
CREATE TABLE businesses (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id       UUID        NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
    name           TEXT        NOT NULL,
    gstin          VARCHAR(15) UNIQUE,
    pan            VARCHAR(10),
    address        TEXT,
    city           TEXT,
    state          TEXT,
    pincode        VARCHAR(6),
    business_type  TEXT,
    is_verified    BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- 3. business_members
-- Junction table linking users to businesses with a role.
-- UNIQUE(business_id, profile_id) prevents duplicate membership.
-- ---------------------------------------------------------------------------
CREATE TABLE business_members (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id   UUID        NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    profile_id    UUID        NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    role          TEXT        NOT NULL DEFAULT 'member',
    invited_by    UUID        REFERENCES profiles(id) ON DELETE SET NULL,
    joined_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (business_id, profile_id)
);

-- ---------------------------------------------------------------------------
-- 4. orders
-- Central record of a commercial transaction between two businesses.
-- buyer_business_id <> seller_business_id enforced by CHECK.
-- ---------------------------------------------------------------------------
CREATE TABLE orders (
    id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    order_number         TEXT        NOT NULL UNIQUE,
    buyer_business_id    UUID        NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    seller_business_id   UUID        NOT NULL REFERENCES businesses(id) ON DELETE RESTRICT,
    created_by           UUID        NOT NULL REFERENCES profiles(id),
    status               TEXT        NOT NULL DEFAULT 'created',
    total_amount         NUMERIC(15,2) NOT NULL,
    currency             VARCHAR(3)  NOT NULL DEFAULT 'INR',
    notes                TEXT,
    expected_delivery_date DATE,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT orders_no_self_order CHECK (buyer_business_id <> seller_business_id),
    CONSTRAINT orders_status_check CHECK (status IN (
        'created', 'confirmed', 'dispatched', 'in_transit',
        'delivered', 'accepted', 'partially_accepted', 'rejected',
        'disputed', 'completed'
    ))
);

-- ---------------------------------------------------------------------------
-- 5. order_items
-- Line-level items for an order. total_price is a generated column.
-- ---------------------------------------------------------------------------
CREATE TABLE order_items (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id    UUID        NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    description TEXT        NOT NULL,
    quantity    NUMERIC(12,3) NOT NULL,
    unit        TEXT        NOT NULL,
    unit_price  NUMERIC(15,2) NOT NULL,
    total_price NUMERIC(15,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    hsn_code    VARCHAR(8),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- 6. deliveries
-- One or more deliveries per order (shipment_number distinguishes shipments).
-- ---------------------------------------------------------------------------
CREATE TABLE deliveries (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id          UUID        NOT NULL REFERENCES orders(id) ON DELETE RESTRICT,
    shipment_number   TEXT        NOT NULL,
    tracking_number   TEXT,
    carrier_name      TEXT,
    driver_name       TEXT,
    driver_phone      TEXT,
    vehicle_number    TEXT,
    dispatched_at     TIMESTAMPTZ,
    estimated_arrival TIMESTAMPTZ,
    delivered_at      TIMESTAMPTZ,
    delivery_address  TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- 7. delivery_events
-- Append-only audit log of delivery lifecycle events. Linked to delivery_id.
-- ---------------------------------------------------------------------------
CREATE TABLE delivery_events (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    delivery_id      UUID        NOT NULL REFERENCES deliveries(id) ON DELETE CASCADE,
    order_id         UUID        NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    event_type       TEXT        NOT NULL,
    performed_by     UUID        NOT NULL REFERENCES profiles(id),
    location         TEXT,
    notes            TEXT,
    accepted_item_ids UUID[],
    rejected_item_ids UUID[],
    rejection_reasons JSONB,
    occurred_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- 8. documents
-- File metadata for order-related documents. sha256_hash is NOT NULL.
-- ---------------------------------------------------------------------------
CREATE TABLE documents (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id       UUID        NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    uploaded_by    UUID        NOT NULL REFERENCES profiles(id),
    document_type  TEXT        NOT NULL,
    file_name      TEXT        NOT NULL,
    storage_path   TEXT        NOT NULL,
    file_size_bytes BIGINT   NOT NULL,
    mime_type      TEXT        NOT NULL,
    sha256_hash    TEXT        NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- 9. disputes
-- Formal dispute raised against an order. resolved_by uses SET NULL.
-- ---------------------------------------------------------------------------
CREATE TABLE disputes (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id     UUID        NOT NULL REFERENCES orders(id) ON DELETE RESTRICT,
    raised_by    UUID        NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
    reason       TEXT        NOT NULL,
    status       TEXT        NOT NULL DEFAULT 'open',
    resolution   TEXT,
    resolved_by  UUID        REFERENCES profiles(id) ON DELETE SET NULL,
    raised_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at  TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- 10. blockchain_transactions
-- Polymorphic on-chain audit records. entity_type/entity_id references any domain entity.
-- Append-only: never updated or deleted after insertion.
-- ---------------------------------------------------------------------------
CREATE TABLE blockchain_transactions (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    entity_type    TEXT        NOT NULL CHECK (entity_type IN ('order', 'delivery', 'document', 'dispute')),
    entity_id      UUID        NOT NULL,
    tx_hash        VARCHAR(66) NOT NULL UNIQUE,
    block_number   BIGINT,
    contract_address VARCHAR(42),
    event_name     TEXT        NOT NULL CHECK (event_name IN (
        'OrderCreated', 'DeliveryDispatched', 'DeliveryDelivered',
        'AcceptanceRecorded', 'PartialAcceptanceRecorded',
        'DisputeRaised', 'DisputeResolved'
    )),
    event_data     JSONB,
    network        TEXT        NOT NULL DEFAULT 'sepolia',
    confirmed_at   TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- Indexes
-- ============================================================================

-- orders
CREATE INDEX idx_orders_buyer_business_id ON orders(buyer_business_id);
CREATE INDEX idx_orders_seller_business_id ON orders(seller_business_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_created_at ON orders(created_at DESC);

-- order_items
CREATE INDEX idx_order_items_order_id ON order_items(order_id);

-- deliveries
CREATE INDEX idx_deliveries_order_id ON deliveries(order_id);
CREATE INDEX idx_deliveries_shipment_number ON deliveries(shipment_number);

-- delivery_events
CREATE INDEX idx_delivery_events_delivery_id ON delivery_events(delivery_id);
CREATE INDEX idx_delivery_events_order_id ON delivery_events(order_id);
CREATE INDEX idx_delivery_events_occurred_at ON delivery_events(occurred_at DESC);
CREATE INDEX idx_delivery_events_event_type ON delivery_events(event_type);

-- documents
CREATE INDEX idx_documents_order_id ON documents(order_id);

-- disputes
CREATE INDEX idx_disputes_order_id ON disputes(order_id);

-- blockchain_transactions
CREATE INDEX idx_blockchain_entity ON blockchain_transactions(entity_type, entity_id);
CREATE INDEX idx_blockchain_confirmed_at ON blockchain_transactions(confirmed_at DESC);

-- business_members
CREATE INDEX idx_business_members_business_id ON business_members(business_id);

-- ============================================================================
-- End of migration 001
-- ============================================================================