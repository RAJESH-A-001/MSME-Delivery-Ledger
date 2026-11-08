-- ============================================================================
-- Migration 002: Triggers and Functions — MSME Delivery & Acceptance Ledger
-- Creates helper functions and triggers for:
--   - automatic updated_at maintenance
--   - append-only enforcement on delivery_events and blockchain_transactions
--   - auto profile creation on new Supabase Auth signup
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Function: set_updated_at
-- Updates the updated_at column to NOW() on any UPDATE.
-- Used by profiles, businesses, orders, deliveries, disputes.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- Triggers: updated_at on tables that have an updated_at column
-- ---------------------------------------------------------------------------
CREATE TRIGGER trigger_profiles_updated_at
    BEFORE UPDATE ON profiles
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trigger_businesses_updated_at
    BEFORE UPDATE ON businesses
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trigger_orders_updated_at
    BEFORE UPDATE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trigger_deliveries_updated_at
    BEFORE UPDATE ON deliveries
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trigger_disputes_updated_at
    BEFORE UPDATE ON disputes
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------------
-- Function: enforce_append_only
-- Rejects any UPDATE or DELETE on append-only tables.
-- Used by delivery_events and blockchain_transactions.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION enforce_append_only()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION
        'Append-only table %: UPDATE and DELETE operations are prohibited.',
        TG_TABLE_NAME
        USING ERRCODE = '42501';
    RETURN NULL; -- unreachable, but required by PL/pgSQL
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- Triggers: append-only enforcement
-- ---------------------------------------------------------------------------
CREATE TRIGGER trigger_delivery_events_append_only
    BEFORE UPDATE OR DELETE ON delivery_events
    FOR EACH ROW
    EXECUTE FUNCTION enforce_append_only();

CREATE TRIGGER trigger_blockchain_transactions_append_only
    BEFORE UPDATE OR DELETE ON blockchain_transactions
    FOR EACH ROW
    EXECUTE FUNCTION enforce_append_only();

-- ---------------------------------------------------------------------------
-- Function: create_profile_on_signup
-- Automatically creates a profiles row when a new user signs up via
-- Supabase Auth. The profiles.id mirrors auth.users.id.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_profile_on_signup()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.profiles (id, full_name, phone, avatar_url, created_at, updated_at)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data ->> 'full_name', NULL),
        COALESCE(NEW.raw_user_meta_data ->> 'phone', NULL),
        COALESCE(NEW.raw_user_meta_data ->> 'avatar_url', NULL),
        NOW(),
        NOW()
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- Trigger: auto-create profile on new auth.users insert
-- ---------------------------------------------------------------------------
CREATE TRIGGER trigger_create_profile_on_signup
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION create_profile_on_signup();

-- ============================================================================
-- End of migration 002
-- ============================================================================