-- ============================================================================
-- Migration 004: Supabase Storage — Order Documents Bucket & Policies
-- Creates the private `order-documents` bucket with upload-only access for
-- authenticated users. Bucket is private; all reads go through backend-generated
-- signed URLs. No direct read policy is created on the bucket.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Create the private order-documents bucket
-- public = false means private bucket (no public read access)
-- ---------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'order-documents',
    'order-documents',
    false,
    104857600,  -- 100 MB max file size
    ARRAY[
        'application/pdf',
        'image/jpeg',
        'image/png',
        'image/webp',
        'text/plain',
        'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.ms-excel',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    ]
)
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Storage policies on storage.objects
-- ============================================================================
-- Upload policy: authenticated users may upload only to `{auth.uid()}/...`
-- path prefix. This ensures each user can only write into their own folder.
-- ---------------------------------------------------------------------------

CREATE POLICY storage_order_documents_upload ON storage.objects
    FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'order-documents'
        AND name LIKE (auth.uid()::text || '/%')
    );

-- ---------------------------------------------------------------------------
-- No SELECT/READ policy on storage.objects for authenticated users.
-- All reads are served via backend-generated signed URLs after participant
-- verification in FastAPI. This prevents unauthorised direct object access.
--
-- service_role (backend) can read/write all objects (bypasses storage policies).
-- ---------------------------------------------------------------------------

-- ============================================================================
-- End of migration 004
-- ============================================================================