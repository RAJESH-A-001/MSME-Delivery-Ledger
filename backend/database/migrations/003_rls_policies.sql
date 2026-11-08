-- ============================================================================
-- Migration 003: Row Level Security (RLS) Policies — MSME Delivery & Acceptance Ledger
-- Enables RLS on all 10 tables and creates the approved security policies.
-- service_role bypasses RLS entirely (used by FastAPI backend).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Enable RLS on all tables
-- ---------------------------------------------------------------------------
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE businesses ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- Helper: is_order_participant
-- Returns true if auth.uid() is a member of either the buyer or seller
-- business of the given order.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION is_order_participant(order_uuid UUID)
RETURNS BOOLEAN AS $$
DECLARE
    result BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM public.business_members
        WHERE business_id IN (
            SELECT buyer_business_id FROM public.orders WHERE id = order_uuid
            UNION
            SELECT seller_business_id FROM public.orders WHERE id = order_uuid
        )
        AND profile_id = auth.uid()
    ) INTO result;
    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- ---------------------------------------------------------------------------
-- Helper: is_business_member
-- Returns true if auth.uid() is a member of the given business.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION is_business_member(business_uuid UUID)
RETURNS BOOLEAN AS $$
DECLARE
    result BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM public.business_members
        WHERE business_id = business_uuid
        AND profile_id = auth.uid()
    ) INTO result;
    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- ---------------------------------------------------------------------------
-- Helper: is_business_owner_or_admin
-- Returns true if auth.uid() is owner or admin member of the given business.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION is_business_owner_or_admin(business_uuid UUID)
RETURNS BOOLEAN AS $$
DECLARE
    result BOOLEAN;
BEGIN
    SELECT (
        auth.uid() = (SELECT owner_id FROM public.businesses WHERE id = business_uuid)
        OR EXISTS (
            SELECT 1 FROM public.business_members
            WHERE business_id = business_uuid
            AND profile_id = auth.uid()
            AND role IN ('owner', 'admin')
        )
    ) INTO result;
    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;
ALTER TABLE public.business_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.disputes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.blockchain_transactions ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- profiles policies
-- ============================================================================

CREATE POLICY profiles_select_own ON profiles
    FOR SELECT TO authenticated
    USING (auth.uid() = id);

CREATE POLICY profiles_insert_own ON profiles
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = id);

CREATE POLICY profiles_update_own ON profiles
    FOR UPDATE TO authenticated
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- ============================================================================
-- businesses policies
-- ============================================================================

CREATE POLICY businesses_select_all ON businesses
    FOR SELECT TO authenticated
    USING (auth.role() = 'authenticated');

CREATE POLICY businesses_insert_all ON businesses
    FOR INSERT TO authenticated
    WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY businesses_update_owner_admin ON businesses
    FOR UPDATE TO authenticated
    USING (public.is_business_owner_or_admin(id))
    WITH CHECK (public.is_business_owner_or_admin(id));

CREATE POLICY businesses_delete_owner ON businesses
    FOR DELETE TO authenticated
    USING (auth.uid() = owner_id);

-- ============================================================================
-- business_members policies
-- ============================================================================

CREATE POLICY business_members_select_member ON business_members
    FOR SELECT TO authenticated
    USING (public.is_business_member(business_id));

CREATE POLICY business_members_insert_owner_admin ON business_members
    FOR INSERT TO authenticated
    WITH CHECK (public.is_business_owner_or_admin(business_id));

CREATE POLICY business_members_update_owner_admin ON business_members
    FOR UPDATE TO authenticated
    USING (public.is_business_owner_or_admin(business_id))
    WITH CHECK (public.is_business_owner_or_admin(business_id));

CREATE POLICY business_members_delete_owner_admin_self ON business_members
    FOR DELETE TO authenticated
    USING (
        public.is_business_owner_or_admin(business_id)
        OR profile_id = auth.uid()
    );

-- ============================================================================
-- orders policies
-- ============================================================================

CREATE POLICY orders_select_participant ON orders
    FOR SELECT TO authenticated
    USING (public.is_order_participant(id));

CREATE POLICY orders_insert_buyer ON orders
    FOR INSERT TO authenticated
    WITH CHECK (
        public.is_business_member(buyer_business_id)
        AND created_by = auth.uid()
    );

CREATE POLICY orders_update_buyer_created ON orders
    FOR UPDATE TO authenticated
    USING (
        public.is_business_member(buyer_business_id)
        AND status = 'created'
    )
    WITH CHECK (
        public.is_business_member(buyer_business_id)
        AND status = 'created'
    );

CREATE POLICY orders_update_seller_confirm_dispatch ON orders
    FOR UPDATE TO authenticated
    USING (
        public.is_business_member(seller_business_id)
        AND status IN ('created', 'confirmed')
    )
    WITH CHECK (
        public.is_business_member(seller_business_id)
        AND status IN ('created', 'confirmed')
    );

-- ---------------------------------------------------------------------------
-- Column-level UPDATE privileges on orders
-- Restricts which columns authenticated users can modify.
-- Protected fields (total_amount, buyer/seller business IDs, ownership,
-- order_number, id, timestamps) are NOT updatable by authenticated users.
-- Only status, notes, and expected_delivery_date can be updated via RLS policies.
-- ---------------------------------------------------------------------------
REVOKE UPDATE ON orders FROM authenticated;
GRANT UPDATE (status, notes, expected_delivery_date) ON orders TO authenticated;

-- ---------------------------------------------------------------------------
-- Table-level privileges for authenticated role
-- Required so that RLS policies can be evaluated. Without these grants,
-- authenticated users receive "permission denied" before RLS is consulted.
-- Grants do NOT bypass RLS; every access is still subject to row-level policies.
-- ---------------------------------------------------------------------------

-- SELECT on all 10 application tables (all have SELECT RLS policies)
GRANT SELECT ON profiles TO authenticated;
GRANT SELECT ON businesses TO authenticated;
GRANT SELECT ON business_members TO authenticated;
GRANT SELECT ON orders TO authenticated;
GRANT SELECT ON order_items TO authenticated;
GRANT SELECT ON deliveries TO authenticated;
GRANT SELECT ON delivery_events TO authenticated;
GRANT SELECT ON documents TO authenticated;
GRANT SELECT ON disputes TO authenticated;
GRANT SELECT ON blockchain_transactions TO authenticated;

-- INSERT on 9 tables with client INSERT policies
-- blockchain_transactions is excluded — service_role only
GRANT INSERT ON profiles TO authenticated;
GRANT INSERT ON businesses TO authenticated;
GRANT INSERT ON business_members TO authenticated;
GRANT INSERT ON orders TO authenticated;
GRANT INSERT ON order_items TO authenticated;
GRANT INSERT ON deliveries TO authenticated;
GRANT INSERT ON delivery_events TO authenticated;
GRANT INSERT ON documents TO authenticated;
GRANT INSERT ON disputes TO authenticated;

-- UPDATE: only orders has client UPDATE policies (3 columns, already granted above)
-- No UPDATE grants on other tables — all client UPDATE policies are "not permitted"

-- ============================================================================
-- order_items policies
-- ============================================================================

CREATE POLICY order_items_select_participant ON order_items
    FOR SELECT TO authenticated
    USING (public.is_order_participant(order_id));

CREATE POLICY order_items_insert_buyer_created ON order_items
    FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.orders
            WHERE orders.id = order_items.order_id
            AND orders.buyer_business_id IN (
                SELECT business_id FROM public.business_members
                WHERE profile_id = auth.uid()
            )
            AND orders.status = 'created'
        )
    );

CREATE POLICY order_items_update_buyer_created ON order_items
    FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.orders
            WHERE orders.id = order_items.order_id
            AND orders.buyer_business_id IN (
                SELECT business_id FROM public.business_members
                WHERE profile_id = auth.uid()
            )
            AND orders.status = 'created'
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.orders
            WHERE orders.id = order_items.order_id
            AND orders.buyer_business_id IN (
                SELECT business_id FROM public.business_members
                WHERE profile_id = auth.uid()
            )
            AND orders.status = 'created'
        )
    );

-- ============================================================================
-- deliveries policies
-- ============================================================================

CREATE POLICY deliveries_select_participant ON deliveries
    FOR SELECT TO authenticated
    USING (public.is_order_participant(order_id));

CREATE POLICY deliveries_insert_seller ON deliveries
    FOR INSERT TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.orders
            WHERE orders.id = deliveries.order_id
            AND orders.seller_business_id IN (
                SELECT business_id FROM public.business_members
                WHERE profile_id = auth.uid()
            )
        )
    );

CREATE POLICY deliveries_update_seller ON deliveries
    FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.orders
            WHERE orders.id = deliveries.order_id
            AND orders.seller_business_id IN (
                SELECT business_id FROM public.business_members
                WHERE profile_id = auth.uid()
            )
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.orders
            WHERE orders.id = deliveries.order_id
            AND orders.seller_business_id IN (
                SELECT business_id FROM public.business_members
                WHERE profile_id = auth.uid()
            )
        )
    );

-- ============================================================================
-- delivery_events policies
-- ============================================================================

CREATE POLICY delivery_events_select_participant ON delivery_events
    FOR SELECT TO authenticated
    USING (public.is_order_participant(order_id));

CREATE POLICY delivery_events_insert_participant ON delivery_events
    FOR INSERT TO authenticated
    WITH CHECK (
        public.is_order_participant(order_id)
        AND performed_by = auth.uid()
    );

-- UPDATE: not permitted (append-only, enforced by trigger)
-- DELETE: not permitted (append-only, enforced by trigger)

-- ============================================================================
-- documents policies
-- ============================================================================

CREATE POLICY documents_select_participant ON documents
    FOR SELECT TO authenticated
    USING (public.is_order_participant(order_id));

CREATE POLICY documents_insert_participant ON documents
    FOR INSERT TO authenticated
    WITH CHECK (
        public.is_order_participant(order_id)
        AND uploaded_by = auth.uid()
    );

-- UPDATE: not permitted for clients (service_role handles metadata)
-- DELETE: not permitted (no policy → deny all)

-- ============================================================================
-- disputes policies
-- ============================================================================

CREATE POLICY disputes_select_participant ON disputes
    FOR SELECT TO authenticated
    USING (public.is_order_participant(order_id));

CREATE POLICY disputes_insert_participant ON disputes
    FOR INSERT TO authenticated
    WITH CHECK (
        public.is_order_participant(order_id)
        AND raised_by = auth.uid()
    );

-- UPDATE: not permitted for clients (service_role only)
-- DELETE: not permitted (no policy → deny all)

-- ============================================================================
-- blockchain_transactions policies
-- ============================================================================

CREATE POLICY blockchain_transactions_select_participant ON blockchain_transactions
    FOR SELECT TO authenticated
    USING (
        (entity_type = 'order' AND public.is_order_participant(entity_id))
        OR (entity_type = 'delivery' AND public.is_order_participant(
            (SELECT order_id FROM public.deliveries WHERE id = entity_id)
        ))
        OR (entity_type = 'document' AND public.is_order_participant(
            (SELECT order_id FROM public.documents WHERE id = entity_id)
        ))
        OR (entity_type = 'dispute' AND public.is_order_participant(
            (SELECT order_id FROM public.disputes WHERE id = entity_id)
        ))
    );

-- INSERT: not permitted for clients (service_role only)
-- UPDATE: not permitted for clients (append-only, enforced by trigger)
-- DELETE: not permitted (append-only, enforced by trigger)

-- ============================================================================
-- End of migration 003
-- ============================================================================