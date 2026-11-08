# Database Security Design

This document describes the intended Row Level Security (RLS) policies, storage access controls, and backend authorization strategy for the MSME Delivery & Acceptance Ledger. **Nothing described here has been implemented yet.** This is a design reference to guide Milestone 4 implementation. All policy descriptions are written in plain English and pseudocode — no SQL is included.

---

## Roles and Actors

The system recognizes three principal roles at the Supabase level:

| Role | Description |
|---|---|
| `anon` | An unauthenticated visitor. Has no session. Must not be able to read or write any application data. |
| `authenticated` | A user who has completed Supabase Auth sign-in. Has a valid JWT. `auth.uid()` returns their UUID; `auth.role()` returns `'authenticated'`. All end-users of the app operate under this role. |
| `service_role` | A privileged backend identity used exclusively by the FastAPI server. Holds the Supabase service role key. **Completely bypasses RLS.** Must never be exposed to the client. |

### How the Two Key Types Are Used

- **Frontend / client SDK** uses the `anon` publishable key. Once a user signs in via Supabase Auth, their JWT is attached to every request. All queries from the frontend are subject to RLS.
- **FastAPI backend** uses the `service_role` secret key. It bypasses RLS entirely and is responsible for enforcing all business-logic-level authorization in its route handlers. The service role key is loaded from server-side environment variables only and is never returned to clients in any API response.

This two-layer model means RLS acts as a **defense-in-depth** safeguard against direct SDK misuse, while FastAPI provides **fine-grained workflow and role enforcement**.

---

## Row Level Security (RLS) Policy Proposals

RLS must be enabled on every table. The default stance is **deny all** — no policy means no access. Each policy below describes the intended access rule in plain English and pseudocode.

---

### `profiles`

Stores one row per registered user (linked 1:1 to `auth.users`).

**SELECT**
- A user may read their own profile row.
  > `auth.uid() = profiles.id`
- `service_role` bypasses RLS and can read all profiles.

**INSERT**
- A user may insert their own profile row (typically triggered automatically on sign-up via a database trigger or Edge Function).
  > `auth.uid() = profiles.id`

**UPDATE**
- A user may update only their own profile row.
  > `auth.uid() = profiles.id`

**DELETE**
- Not permitted via RLS. Account deletion is a backend-controlled operation performed by `service_role`.

---

### `businesses`

Stores registered business entities. Any authenticated user may discover businesses (needed during order creation to look up counterparties).

**SELECT**
- Any `authenticated` user can read any business row.
  > `auth.role() = 'authenticated'`

**INSERT**
- Any `authenticated` user can create a business (they become its owner).
  > `auth.role() = 'authenticated'`

**UPDATE**
- Only the business owner or a member with the `admin` role may update business details.
  > `auth.uid() = businesses.owner_id`  
  > OR  
  > `EXISTS (SELECT 1 FROM business_members WHERE business_id = businesses.id AND user_id = auth.uid() AND role = 'admin')`

**DELETE**
- Only the business owner may delete the business.
  > `auth.uid() = businesses.owner_id`

---

### `business_members`

Junction table linking users to businesses with a role (`owner`, `admin`, `member`).

**SELECT**
- A user may view the member list of any business they themselves belong to.
  > `EXISTS (SELECT 1 FROM business_members bm2 WHERE bm2.business_id = business_members.business_id AND bm2.profile_id = auth.uid())`

**INSERT**
- Only the business owner or an `admin` member may add new members.
  > `EXISTS (SELECT 1 FROM business_members bm2 WHERE bm2.business_id = business_members.business_id AND bm2.profile_id = auth.uid() AND bm2.role IN ('owner', 'admin'))`

**UPDATE**
- Only the business owner or an `admin` member may change another member's role.
  > Same check as INSERT above.

**DELETE**
- The business owner or an `admin` member may remove any member.
  > Same check as INSERT above.
- A user may remove themselves from a business (self-exit).
  > `business_members.profile_id = auth.uid()`

---

### `orders`

The central transaction record. Access is scoped to participants of the buyer or seller business.

A helper concept used throughout: **"order participant"** — a user who is a member of either `buyer_business_id` or `seller_business_id` on the order row.

> `is_order_participant(order_row) =`  
> `EXISTS (SELECT 1 FROM business_members WHERE business_id IN (order_row.buyer_business_id, order_row.seller_business_id) AND profile_id = auth.uid())`

**SELECT**
- User must be an order participant.
  > `is_order_participant(orders)`

**INSERT**
- User must be a member of the `buyer_business_id` on the row being inserted (buyers initiate orders).
  > `EXISTS (SELECT 1 FROM business_members WHERE business_id = orders.buyer_business_id AND profile_id = auth.uid())`

**UPDATE**
- Buyer members may update orders whose status is `'created'` (e.g., editing items before confirmation).
  > `orders.status = 'created'`  
  > AND `EXISTS (SELECT 1 FROM business_members WHERE business_id = orders.buyer_business_id AND profile_id = auth.uid())`
- Seller members may transition an order to `'confirmed'` or `'dispatched'`.
  > `EXISTS (SELECT 1 FROM business_members WHERE business_id = orders.seller_business_id AND profile_id = auth.uid())`
- Note: Status transition validity (e.g., `created → confirmed → dispatched → delivered`) is enforced at the **application layer in FastAPI**, not in RLS.

**DELETE**
- **Not permitted.** Orders are permanent audit records. No RLS policy grants DELETE to any role.

---

### `order_items`

Line items belonging to an order.

**SELECT**
- Readable if the user can read the parent order (is an order participant).
  > `EXISTS (SELECT 1 FROM orders WHERE orders.id = order_items.order_id AND is_order_participant(orders))`

**INSERT**
- Insertable by buyer members when the parent order is in `'created'` status.
  > `EXISTS (SELECT 1 FROM orders WHERE orders.id = order_items.order_id AND orders.status = 'created')`  
  > AND `EXISTS (SELECT 1 FROM business_members WHERE business_id = (SELECT buyer_business_id FROM orders WHERE id = order_items.order_id) AND profile_id = auth.uid())`

**UPDATE**
- Same conditions as INSERT (buyer member, order in `'created'` status).

**DELETE**
- **Not permitted.** Item records are part of the audit trail.

---

### `deliveries`

Tracks the delivery record associated with an order (assigned driver, vehicle, expected delivery date).

**SELECT**
- Readable by any order participant of the linked order.
  > `EXISTS (SELECT 1 FROM orders WHERE orders.id = deliveries.order_id AND is_order_participant(orders))`

**INSERT**
- Insertable by seller members (they arrange dispatch) or by `service_role`.
  > `EXISTS (SELECT 1 FROM business_members WHERE business_id = (SELECT seller_business_id FROM orders WHERE id = deliveries.order_id) AND user_id = auth.uid())`

**UPDATE**
- Updatable by seller members or `service_role` (e.g., updating driver assignment, dispatch time, delivery confirmation).
  > Same membership check as INSERT.

**DELETE**
- Not permitted via RLS.

---

### `delivery_events`

Append-only event log for delivery status changes (e.g., `dispatched`, `out_for_delivery`, `delivered`, `failed`).

**SELECT**
- Readable by any order participant of the linked order.
  > Traverse `delivery_events → deliveries → orders` and apply `is_order_participant(orders)`.

**INSERT**
- Order participants may insert events (e.g., buyer records acceptance; seller records dispatch).
  > `is_order_participant(linked order)`
- `service_role` may also insert on behalf of system-generated events (e.g., blockchain confirmation hooks).

**UPDATE**
- **Not permitted.** Events are immutable once written. Enforced by database trigger at the schema level.

**DELETE**
- **Not permitted.** Append-only log. Enforced by database trigger at the schema level.

---

### `documents`

Uploaded files (invoices, delivery receipts, acceptance certificates) linked to an order.

**SELECT**
- Readable by order participants of the linked order.
  > `is_order_participant(linked order)`
- `service_role` can read all documents (needed for blockchain hashing, dispute resolution).

**INSERT**
- Any order participant may upload a document for their order.
  > `is_order_participant(linked order)`

**UPDATE**
- Not permitted via client. Document metadata updates (e.g., blockchain hash after on-chain confirmation) are performed by `service_role`.

**DELETE**
- **Not permitted.** Documents form the tamper-evident audit trail.

---

### `disputes`

Formal disputes raised against an order.

**SELECT**
- Readable by order participants of the disputed order.
  > `is_order_participant(linked order)`

**INSERT**
- Any order participant may raise a dispute.
  > `is_order_participant(linked order)`

**UPDATE**
- **Only `service_role` may update a dispute row.** Resolution (setting `status`, `resolution_notes`, `resolved_at`) is a backend-only operation. No client-side RLS UPDATE policy is granted.

**DELETE**
- **Not permitted.**

---

### `blockchain_transactions`

Records of on-chain transaction submissions and confirmations (tx hashes, block numbers, event data).

**SELECT**
- Any `authenticated` user who is an order participant may read the blockchain records linked to their orders.
  > `is_order_participant(linked order)`

**INSERT**
- **Only `service_role`.** Blockchain submissions are initiated and recorded exclusively by the FastAPI backend after on-chain confirmation. No client INSERT policy.

**UPDATE**
- **Only `service_role`.** Status updates (e.g., `pending → confirmed`) are written by the backend worker. No client UPDATE policy. Enforced by database trigger at the schema level — no row may be modified after insert.

**DELETE**
- **Not permitted.** Enforced by database trigger at the schema level — no row may be deleted after insert.

---

## Supabase Storage Security

### Bucket: `order-documents`

This is the sole storage bucket for all application file uploads.

| Property | Value |
|---|---|
| Visibility | **Private** — public access disabled at bucket level |
| Allowed file types | PDF, images (JPEG, PNG), XLSX |
| Max file size | Enforced by backend (recommended: 20 MB) |

### Upload Policy

- Authenticated users may upload files only to path prefixes that begin with their own `auth.uid()`.
  > Allowed path pattern: `{auth.uid()}/{order_id}/{filename}`
- This prevents a user from writing into another user's folder namespace.
- FastAPI validates that the `order_id` in the path corresponds to an order the user is a participant of before generating an upload URL.

### Download / Read Policy

- **No direct public read access** to any object in `order-documents`.
- Downloads are always mediated by the FastAPI backend:
  1. Client requests a download link from FastAPI (`GET /orders/{id}/documents/{doc_id}/download`).
  2. FastAPI verifies the user is an order participant.
  3. FastAPI uses `service_role` to call Supabase Storage and generate a **short-lived signed URL** (recommended TTL: 5–15 minutes).
  4. FastAPI returns the signed URL to the client.
  5. The client fetches the file directly from the signed URL.
- Raw storage object paths are **never returned** in API responses; only signed URLs are exposed.

### Direct Public Access

Disabled. The bucket policy must deny all unauthenticated reads. Even authenticated direct SDK reads are blocked — all access is routed through the backend.

---

## Backend Authorization Layer

The FastAPI backend uses the `service_role` key and therefore **bypasses all RLS policies**. This means FastAPI must enforce its own authorization rules rigorously in every route handler before performing any database operation.

### Responsibility Separation

| Layer | Responsibility |
|---|---|
| **Supabase RLS** | Coarse-grained data isolation. Protects against accidental or malicious direct SDK calls that bypass the API (e.g., client SDK queries). Acts as a last-resort safety net. |
| **FastAPI route handlers** | Fine-grained business logic: status transition validation, role-based permission checks, workflow rule enforcement, rate limiting, input validation. |

### FastAPI Authorization Rules (examples)

- Before any order mutation, verify the calling user (extracted from the Bearer JWT) is a member of the relevant business.
- Enforce status machine transitions explicitly: reject any request that attempts an invalid transition (e.g., `delivered → created`).
- When generating upload URLs, verify the target `order_id` belongs to the user before delegating to storage.
- When recording a blockchain transaction, the route must only be reachable by internal service calls or authenticated admin workflows — never exposed as a public endpoint.
- Dispute resolution endpoints must check that the caller has `admin` or `service_role` privileges before updating dispute status.

### Key Management Rules

- The `service_role` key is loaded **only from server-side environment variables** (`SUPABASE_SERVICE_ROLE_KEY`).
- It is **never returned** in any API response body, log entry, or error message.
- The `anon` publishable key is the only Supabase credential included in the frontend bundle.

---

## Sensitive Data Considerations

### GSTIN and PAN (`businesses` table)

- These are government-issued tax identifiers and are sensitive personal/business data.
- In list endpoints (e.g., `GET /businesses`), mask these values (e.g., show only last 4 characters or return `null`).
- Full values should only be returned to the business owner or an `admin` member of that business, verified in the FastAPI handler.

### Driver Phone Numbers (`deliveries` table)

- Phone numbers of assigned drivers must only be visible to order participants (buyer and seller members) of the specific delivery.
- Must not appear in any generic user-facing listing or aggregate query.

### Document File Paths (`documents` table)

- Raw Supabase Storage object paths must **never** be returned in API responses.
- Always substitute with a time-limited signed URL generated server-side.
- If the signed URL expires, the client must request a fresh one from the backend.

### Blockchain `event_data` JSONB (`blockchain_transactions` table)

- The `event_data` column may contain transaction hashes, smart contract event parameters, and other chain data.
- It must **never** contain private keys, wallet seed phrases, or signing material of any kind.
- Backend workers that write to this column must explicitly strip or avoid logging any key material before persisting.
- Review the JSONB schema regularly to ensure no sensitive credential fields are accidentally included.

---

## Implementation Checklist

This checklist tracks all RLS policies to be implemented in **Milestone 4**. Check off each item as it is applied to the database via migration.

### Profiles
- [ ] RLS enabled on `profiles`
- [ ] SELECT policy: user can read own profile (`auth.uid() = id`)
- [ ] INSERT policy: user can insert own profile (`auth.uid() = id`)
- [ ] UPDATE policy: user can update own profile (`auth.uid() = id`)

### Businesses
- [ ] RLS enabled on `businesses`
- [ ] SELECT policy: any authenticated user can read all businesses
- [ ] INSERT policy: any authenticated user can create a business
- [ ] UPDATE policy: owner or admin member can update
- [ ] DELETE policy: owner only can delete

### Business Members
- [ ] RLS enabled on `business_members`
- [ ] SELECT policy: member of same business can view member list
- [ ] INSERT policy: owner or admin can add members
- [ ] UPDATE policy: owner or admin can change member roles
- [ ] DELETE policy: owner or admin can remove members; user can remove self

### Orders
- [ ] RLS enabled on `orders`
- [ ] SELECT policy: order participant (buyer or seller member) can read
- [ ] INSERT policy: buyer member can create orders
- [ ] UPDATE policy: buyer member can update `'created'` status orders; seller member can confirm/dispatch
- [ ] No DELETE policy (deny all deletes)

### Order Items
- [ ] RLS enabled on `order_items`
- [ ] SELECT policy: order participant can read items
- [ ] INSERT policy: buyer member, parent order in `'created'` status
- [ ] UPDATE policy: buyer member, parent order in `'created'` status
- [ ] No DELETE policy

### Deliveries
- [ ] RLS enabled on `deliveries`
- [ ] SELECT policy: order participant can read
- [ ] INSERT policy: seller member can insert
- [ ] UPDATE policy: seller member can update
- [ ] No DELETE policy

### Delivery Events
- [ ] RLS enabled on `delivery_events`
- [ ] SELECT policy: order participant can read
- [ ] INSERT policy: order participant or service_role can insert
- [ ] No UPDATE policy
- [ ] No DELETE policy

### Documents
- [ ] RLS enabled on `documents`
- [ ] SELECT policy: order participant can read
- [ ] INSERT policy: order participant can insert
- [ ] No UPDATE policy (service_role handles metadata updates)
- [ ] No DELETE policy

### Disputes
- [ ] RLS enabled on `disputes`
- [ ] SELECT policy: order participant can read
- [ ] INSERT policy: order participant can raise a dispute
- [ ] No UPDATE policy for clients (service_role only)
- [ ] No DELETE policy

### Blockchain Transactions
- [ ] RLS enabled on `blockchain_transactions`
- [ ] SELECT policy: order participant can read linked transaction records
- [ ] No INSERT policy for clients (service_role only)
- [ ] No UPDATE policy for clients (service_role only)
- [ ] No DELETE policy

### Storage
- [ ] Bucket `order-documents` created as private
- [ ] Public access disabled on bucket
- [ ] Upload policy: authenticated users may upload only to `{auth.uid()}/...` path prefix
- [ ] No direct read policy — all reads via backend-generated signed URLs
- [ ] Backend signed URL generation implemented in FastAPI with participant verification

### Backend / General
- [ ] `SUPABASE_SERVICE_ROLE_KEY` stored only in server-side environment — not in frontend bundle
- [ ] All FastAPI route handlers include participant membership checks before DB operations
- [ ] Status transition guard implemented for order state machine
- [ ] GSTIN/PAN masking implemented in business list responses
- [ ] Raw storage paths stripped from all API responses; signed URLs returned instead
- [ ] `event_data` write path reviewed to ensure no private key material is persisted
