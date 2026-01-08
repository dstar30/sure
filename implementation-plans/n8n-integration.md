# n8n Integration - Implementation Plan

## Table of Contents

1. [Overview](#1-overview)
2. [Requirements](#2-requirements)
   - 2.1 [User Needs](#21-user-needs)
   - 2.2 [Functional Requirements](#22-functional-requirements)
   - 2.3 [Non-Functional Requirements](#23-non-functional-requirements)
3. [Technical Specification](#3-technical-specification)
   - 3.1 [Data Model](#31-data-model)
   - 3.2 [Webhook Security](#32-webhook-security)
   - 3.3 [Webhook Payload Format](#33-webhook-payload-format)
   - 3.4 [API Enhancements](#34-api-enhancements)
   - 3.5 [UI Components](#35-ui-components)
4. [Implementation Plan](#4-implementation-plan)
   - 4.1 [Phase 1: Prerequisites & Data Model](#41-phase-1-prerequisites--data-model)
   - 4.2 [Phase 2: Webhook Security Infrastructure](#42-phase-2-webhook-security-infrastructure)
   - 4.3 [Phase 3: n8n Webhook Endpoint](#43-phase-3-n8n-webhook-endpoint)
   - 4.4 [Phase 4: Bulk Transaction Support](#44-phase-4-bulk-transaction-support)
   - 4.5 [Phase 5: Convenience API Endpoints](#45-phase-5-convenience-api-endpoints)
   - 4.6 [Phase 6: Settings UI for Webhook Management](#46-phase-6-settings-ui-for-webhook-management)
   - 4.7 [Phase 7: Comprehensive Documentation](#47-phase-7-comprehensive-documentation)
   - 4.8 [Phase 8: Testing & Validation](#48-phase-8-testing--validation)

---

## 1. Overview

**What We're Building:**
An n8n integration that enables workflow automation for the Sure financial application. Users can create automated workflows (e.g., adding transactions via Telegram, recurring expense tracking, receipt parsing) using n8n as the orchestration layer. The integration provides secure webhook endpoints, enhanced API endpoints with name-based lookups, and comprehensive documentation.

**Key Components:**
- `WebhookEndpoint` model - Store webhook configurations with per-endpoint secrets
- Webhook signature verification using HMAC-SHA256
- `/webhooks/n8n` endpoint supporting single and bulk transaction creation
- Idempotency support to prevent duplicate transaction processing
- Convenience API endpoints (account/category lookup by name, auto-create merchants)
- Settings UI for webhook management (create, test, view logs, regenerate secrets)
- Comprehensive documentation (Markdown guide, Postman collection, OpenAPI spec)

**Sequencing Logic:**
1. **Data foundation** - Webhook endpoint model and storage
2. **Security infrastructure** - HMAC signature verification
3. **Core webhook endpoint** - Single transaction processing
4. **Bulk operations** - Multiple transactions in one webhook call
5. **Convenience APIs** - Helper endpoints for easier integration
6. **User interface** - Settings page for webhook management
7. **Documentation** - All formats for developer onboarding
8. **Testing & validation** - Comprehensive test coverage

**Key Design Decisions:**
- **Per webhook endpoint secrets** (most flexible, users can create multiple webhooks)
- **HMAC-SHA256 signature verification** (industry standard, same as Stripe)
- **Idempotency keys** (prevent duplicate transactions from retries)
- **Bulk transaction support** (process multiple transactions in one webhook)
- **Name-based lookups** (easier than requiring IDs in workflows)
- **Settings UI** (user-friendly webhook configuration)

---

## 2. Requirements

### 2.1 User Needs

**Primary User Stories:**
- As a user, I want to add transactions via Telegram without opening the app
- As a user, I want to automatically track recurring expenses through n8n workflows
- As a user, I want to parse receipt images and create transactions automatically
- As a user, I want to integrate Sure with other tools in my workflow automation
- As a user, I want to securely configure webhooks without technical knowledge

**Secondary User Stories:**
- As a developer, I want clear API documentation for building n8n workflows
- As a user, I want to see webhook activity and troubleshoot failed calls
- As a user, I want to test my webhook configuration before going live
- As a user, I want to create bulk transactions from spreadsheet imports via n8n

### 2.2 Functional Requirements

**FR-1: Webhook Endpoint Management**
- Users can create multiple webhook endpoints
- Each endpoint has a unique URL and secret
- Endpoints can be enabled/disabled
- Endpoints can be deleted (soft delete with history retention)
- Users can regenerate webhook secrets

**FR-2: Webhook Signature Verification**
- HMAC-SHA256 signature verification for all webhook calls
- Timestamp validation (5-minute tolerance to prevent replay attacks)
- Signature format: `t=<timestamp>,v1=<signature>`
- Reject webhooks with invalid or missing signatures

**FR-3: Transaction Creation via Webhook**
- Support single transaction creation
- Support bulk transaction creation (multiple transactions in one call)
- Idempotency keys to prevent duplicate processing
- Name-based account/category lookup (e.g., "Checking" → account ID)
- Auto-create merchants if not found
- Return transaction IDs in webhook response

**FR-4: Convenience API Endpoints**
- `GET /api/v1/accounts/lookup?name=Checking` - Find account by name
- `GET /api/v1/categories/lookup?name=Food` - Find category by name (fuzzy)
- `POST /api/v1/merchants/find_or_create` - Create merchant if doesn't exist
- Enhanced transaction creation with name-based references

**FR-5: Webhook Activity Logging**
- Log all webhook calls (success and failure)
- Store request payload, response, and processing time
- Retention: 30 days
- Filterable by status, date, endpoint

**FR-6: Settings UI**
- Create new webhook endpoint
- Edit webhook endpoint (name, URL, enabled status)
- View webhook secret (masked by default, click to reveal)
- Regenerate webhook secret with confirmation
- Test webhook endpoint (send test payload)
- View webhook activity log
- Delete webhook endpoint

**FR-7: Documentation**
- Markdown guide with example workflows (Telegram → n8n → Sure)
- Postman collection for API testing
- OpenAPI spec updates for new endpoints
- Code examples in multiple languages (cURL, JavaScript, Python)

### 2.3 Non-Functional Requirements

**Performance:**
- Webhook processing should complete within 2 seconds for single transaction
- Bulk transaction processing (50 transactions) should complete within 10 seconds
- Webhook signature verification should complete within 50ms
- API lookup endpoints should respond within 200ms

**Security:**
- All webhook calls require valid HMAC signature
- Webhook secrets stored encrypted in database
- Secrets never logged or exposed in error messages
- Rate limiting applied to webhook endpoint (500 requests/hour)
- HTTPS required for webhook URLs (reject HTTP in production)

**Reliability:**
- Failed webhook processing logged for debugging
- Idempotency prevents duplicate transaction creation
- Graceful degradation if Redis unavailable (skip idempotency check)
- Return 200 OK even if processing fails (n8n webhook best practice)

**Usability:**
- Clear error messages for webhook validation failures
- Test webhook feature provides immediate feedback
- Webhook secret easily copyable with one click
- Activity log shows human-readable status messages

---

## 3. Technical Specification

### 3.1 Data Model

#### WebhookEndpoint Model

**Table:** `webhook_endpoints`

**Purpose:** Store webhook configurations with per-endpoint secrets

**Columns:**
```ruby
t.references :family, null: false, foreign_key: true, index: true
t.string :name, null: false                    # User-friendly name
t.string :url, null: false                     # Webhook URL (https only in prod)
t.string :secret_encrypted, null: false        # Encrypted HMAC secret
t.boolean :enabled, default: true, null: false # Active/inactive toggle
t.datetime :last_used_at                       # Last successful webhook call
t.integer :success_count, default: 0          # Total successful calls
t.integer :failure_count, default: 0          # Total failed calls
t.timestamps
t.datetime :deleted_at                         # Soft delete
```

**Indexes:**
```ruby
add_index :webhook_endpoints, [:family_id, :enabled]
add_index :webhook_endpoints, :deleted_at
```

**Associations:**
```ruby
belongs_to :family
has_many :webhook_logs, dependent: :destroy
```

**Methods:**
```ruby
# Generate secure random secret (64 characters)
def generate_secret
  SecureRandom.hex(32)
end

# Verify HMAC signature
def verify_signature(payload, signature_header)
  # Implementation in Phase 2
end

# Check if webhook is active
def active?
  enabled? && deleted_at.nil?
end
```

#### WebhookLog Model

**Table:** `webhook_logs`

**Purpose:** Audit log for all webhook calls

**Columns:**
```ruby
t.references :webhook_endpoint, null: false, foreign_key: true, index: true
t.string :status, null: false                  # success, failure, invalid_signature
t.text :request_payload                        # Original payload (truncated if large)
t.text :response_payload                       # Response sent back
t.text :error_message                          # Error details if failed
t.integer :processing_time_ms                  # Processing duration
t.string :idempotency_key                      # For duplicate detection
t.timestamps
```

**Indexes:**
```ruby
add_index :webhook_logs, [:webhook_endpoint_id, :created_at]
add_index :webhook_logs, :idempotency_key
add_index :webhook_logs, :status
```

**Enums:**
```ruby
enum :status, {
  success: "success",
  failure: "failure",
  invalid_signature: "invalid_signature",
  duplicate: "duplicate"
}
```

**Cleanup:**
- Background job runs daily to delete logs older than 30 days
- Keeps database size manageable

### 3.2 Webhook Security

#### HMAC Signature Verification

**Algorithm:** HMAC-SHA256

**Header Format:**
```
X-N8N-Signature: t=1672531200,v1=5f3e8d2a1b4c9f7e6d3a2b1c0f9e8d7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e
```

**Signature Calculation:**
```ruby
# Concatenate timestamp and payload
signed_payload = "#{timestamp}.#{json_payload}"

# Calculate HMAC
signature = OpenSSL::HMAC.hexdigest("SHA256", webhook_secret, signed_payload)

# Format header
header = "t=#{timestamp},v1=#{signature}"
```

**Verification Steps:**
1. Extract timestamp and signature from header
2. Verify timestamp is within 5 minutes of current time (prevent replay)
3. Reconstruct signed payload using timestamp and request body
4. Calculate expected signature using webhook secret
5. Compare calculated signature with provided signature (constant-time comparison)
6. Reject if any step fails

**Security Properties:**
- Prevents tampering (payload modification detected)
- Prevents replay attacks (timestamp validation)
- Constant-time comparison (prevents timing attacks)
- Per-endpoint secrets (compromise of one doesn't affect others)

### 3.3 Webhook Payload Format

#### Single Transaction Creation

**Request:**
```json
POST /webhooks/n8n
X-N8N-Signature: t=1672531200,v1=<signature>
Content-Type: application/json

{
  "type": "transaction.create",
  "idempotency_key": "telegram-msg-123456",
  "data": {
    "account": "Checking",           // Name or UUID
    "amount": 25.50,
    "description": "Coffee at Starbucks",
    "category": "Food & Drink",      // Name or UUID (optional)
    "merchant": "Starbucks",         // Name or UUID (optional, auto-created)
    "date": "2024-01-15",            // YYYY-MM-DD (optional, defaults to today)
    "notes": "Morning coffee",       // Optional
    "tags": ["Personal", "Coffee"],  // Array of tag names or UUIDs (optional)
    "nature": "expense"              // "income" or "expense" (optional, inferred from amount)
  }
}
```

**Response:**
```json
{
  "success": true,
  "transaction": {
    "id": "uuid-here",
    "account_id": "account-uuid",
    "amount": "25.50",
    "date": "2024-01-15",
    "category": {
      "id": "category-uuid",
      "name": "Food & Drink"
    },
    "merchant": {
      "id": "merchant-uuid",
      "name": "Starbucks"
    }
  }
}
```

#### Bulk Transaction Creation

**Request:**
```json
POST /webhooks/n8n
X-N8N-Signature: t=1672531200,v1=<signature>
Content-Type: application/json

{
  "type": "transactions.bulk_create",
  "idempotency_key": "import-2024-01-15",
  "transactions": [
    {
      "account": "Checking",
      "amount": 25.50,
      "description": "Coffee",
      "category": "Food & Drink",
      "date": "2024-01-15"
    },
    {
      "account": "Checking",
      "amount": 12.99,
      "description": "Lunch",
      "category": "Food & Drink",
      "date": "2024-01-15"
    }
  ]
}
```

**Response:**
```json
{
  "success": true,
  "results": [
    {
      "success": true,
      "transaction": { "id": "uuid-1", ... }
    },
    {
      "success": true,
      "transaction": { "id": "uuid-2", ... }
    }
  ],
  "summary": {
    "total": 2,
    "successful": 2,
    "failed": 0
  }
}
```

### 3.4 API Enhancements

#### Account Lookup by Name

**Endpoint:** `GET /api/v1/accounts/lookup`

**Parameters:**
- `name` (required) - Account name to search for
- `exact` (optional, default: false) - Require exact match vs fuzzy

**Response:**
```json
{
  "account": {
    "id": "uuid",
    "name": "Checking Account",
    "type": "depository",
    "currency": "USD"
  }
}
```

**Error (not found):**
```json
{
  "error": "not_found",
  "message": "No account found with name: Savings"
}
```

#### Category Lookup by Name

**Endpoint:** `GET /api/v1/categories/lookup`

**Parameters:**
- `name` (required) - Category name to search for
- `fuzzy` (optional, default: true) - Allow fuzzy matching

**Response:**
```json
{
  "category": {
    "id": "uuid",
    "name": "Food & Drink",
    "classification": "expense",
    "color": "#f97316",
    "icon": "utensils"
  }
}
```

**Fuzzy Matching Examples:**
- "food" → "Food & Drink"
- "gas" → "Gas & Fuel"
- "restaurant" → "Food & Drink" (via alias)

#### Merchant Find or Create

**Endpoint:** `POST /api/v1/merchants/find_or_create`

**Request:**
```json
{
  "name": "Starbucks Coffee",
  "create_if_missing": true
}
```

**Response (existing):**
```json
{
  "merchant": {
    "id": "uuid",
    "name": "Starbucks Coffee",
    "created": false
  }
}
```

**Response (newly created):**
```json
{
  "merchant": {
    "id": "uuid",
    "name": "Starbucks Coffee",
    "created": true
  }
}
```

### 3.5 UI Components

#### Webhook Endpoints Settings Page

**Route:** `/settings/webhooks`

**Features:**
- List of webhook endpoints (table view)
- Create new webhook button (opens modal/form)
- Edit webhook (inline or modal)
- Delete webhook (with confirmation)
- View activity log (expandable or separate page)

**Table Columns:**
- Name
- URL
- Status (Active/Inactive badge)
- Last Used (timestamp)
- Success/Failure count
- Actions (Edit, Test, Delete)

#### Webhook Endpoint Form

**Fields:**
- Name (text input, required)
- URL (URL input, required, validate HTTPS in production)
- Enabled (checkbox, default: true)

**Actions:**
- Save
- Cancel
- Test Webhook (sends test payload)

#### Webhook Secret Display

**Security:**
- Secret masked by default: `••••••••••••••••••••••••••••`
- "Show Secret" button reveals full secret
- "Copy to Clipboard" button for easy copying
- "Regenerate Secret" button (with confirmation warning)

#### Test Webhook Modal

**Purpose:** Send test payload to verify webhook is working

**Flow:**
1. User clicks "Test Webhook" button
2. Modal opens with:
   - Test payload preview (editable JSON)
   - "Send Test" button
3. On send:
   - POST request to webhook URL with test payload
   - Shows loading spinner
4. Result displayed:
   - Success: Green checkmark + response preview
   - Failure: Red X + error message

#### Webhook Activity Log

**Display:**
- Table with recent webhook calls (last 100)
- Filters: Status (all/success/failure), Date range
- Expandable rows showing full request/response payloads

**Columns:**
- Timestamp
- Status (badge: green/red/yellow)
- Processing time (ms)
- Idempotency key
- Error message (if failed)
- Actions (View Details)

---

## 4. Implementation Plan

### 4.1 Phase 1: Prerequisites & Data Model

**Justification:** Implements spec section 3.1 (Data Model). Foundation for webhook endpoint storage and logging.

**Tasks:**

- [ ] Review existing webhook and API patterns
  - Read `app/controllers/webhooks_controller.rb` to understand Plaid/Stripe webhook patterns
  - Read `app/controllers/api/v1/base_controller.rb` to understand authentication and error handling
  - Review `app/models/api_key.rb` for encrypted key storage patterns
  - Study signature verification in existing webhooks

- [ ] Create migration for `webhook_endpoints` table
  ```ruby
  # db/migrate/YYYYMMDDHHMMSS_create_webhook_endpoints.rb
  class CreateWebhookEndpoints < ActiveRecord::Migration[8.0]
    def change
      create_table :webhook_endpoints do |t|
        t.references :family, null: false, foreign_key: true, index: true
        t.string :name, null: false
        t.string :url, null: false
        t.string :secret_encrypted, null: false
        t.boolean :enabled, default: true, null: false
        t.datetime :last_used_at
        t.integer :success_count, default: 0, null: false
        t.integer :failure_count, default: 0, null: false
        t.datetime :deleted_at

        t.timestamps
      end

      add_index :webhook_endpoints, [:family_id, :enabled]
      add_index :webhook_endpoints, :deleted_at
    end
  end
  ```

- [ ] Create migration for `webhook_logs` table
  ```ruby
  # db/migrate/YYYYMMDDHHMMSS_create_webhook_logs.rb
  class CreateWebhookLogs < ActiveRecord::Migration[8.0]
    def change
      create_table :webhook_logs do |t|
        t.references :webhook_endpoint, null: false, foreign_key: true, index: true
        t.string :status, null: false
        t.text :request_payload
        t.text :response_payload
        t.text :error_message
        t.integer :processing_time_ms
        t.string :idempotency_key

        t.timestamps
      end

      add_index :webhook_logs, [:webhook_endpoint_id, :created_at]
      add_index :webhook_logs, :idempotency_key
      add_index :webhook_logs, :status
    end
  end
  ```

- [ ] Create `WebhookEndpoint` model in `app/models/webhook_endpoint.rb`
  ```ruby
  # == Schema Information
  #
  # Table name: webhook_endpoints
  #
  #  id               :bigint           not null, primary key
  #  deleted_at       :datetime
  #  enabled          :boolean          default(TRUE), not null
  #  failure_count    :integer          default(0), not null
  #  last_used_at     :datetime
  #  name             :string           not null
  #  secret_encrypted :string           not null
  #  success_count    :integer          default(0), not null
  #  url              :string           not null
  #  created_at       :datetime         not null
  #  updated_at       :datetime         not null
  #  family_id        :bigint           not null
  #
  # Indexes
  #
  #  index_webhook_endpoints_on_deleted_at          (deleted_at)
  #  index_webhook_endpoints_on_family_id           (family_id)
  #  index_webhook_endpoints_on_family_id_and_enabled (family_id,enabled)
  #
  class WebhookEndpoint < ApplicationRecord
    belongs_to :family
    has_many :webhook_logs, dependent: :destroy

    # Encrypt webhook secret using Rails encryption
    encrypts :secret_encrypted, deterministic: false

    validates :name, presence: true, length: { maximum: 100 }
    validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
    validate :validate_https_in_production

    # Scopes
    scope :active, -> { where(enabled: true, deleted_at: nil) }
    scope :inactive, -> { where(enabled: false) }
    scope :deleted, -> { where.not(deleted_at: nil) }
    scope :ordered, -> { order(created_at: :desc) }

    # Callbacks
    before_create :generate_secret, unless: :secret_encrypted?

    # Generate secure random secret (64-character hex)
    #
    # @return [String] Generated secret
    def generate_secret
      secret = SecureRandom.hex(32)
      self.secret_encrypted = secret
      secret
    end

    # Regenerate webhook secret
    #
    # @return [String] New secret
    def regenerate_secret!
      secret = generate_secret
      save!
      secret
    end

    # Get decrypted secret for display/use
    #
    # @return [String] Decrypted secret
    def secret
      secret_encrypted
    end

    # Record successful webhook call
    def record_success!
      increment!(:success_count)
      touch(:last_used_at)
    end

    # Record failed webhook call
    def record_failure!
      increment!(:failure_count)
    end

    # Check if webhook is active
    #
    # @return [Boolean]
    def active?
      enabled? && !deleted?
    end

    # Check if webhook is deleted (soft delete)
    #
    # @return [Boolean]
    def deleted?
      deleted_at.present?
    end

    # Soft delete webhook endpoint
    def soft_delete!
      update!(deleted_at: Time.current, enabled: false)
    end

    # Restore deleted webhook
    def restore!
      update!(deleted_at: nil)
    end

    private

    def validate_https_in_production
      return unless Rails.env.production?
      return if url.blank?

      unless url.start_with?("https://")
        errors.add(:url, "must use HTTPS in production")
      end
    end
  end
  ```

- [ ] Create `WebhookLog` model in `app/models/webhook_log.rb`
  ```ruby
  # == Schema Information
  #
  # Table name: webhook_logs
  #
  #  id                 :bigint           not null, primary key
  #  error_message      :text
  #  idempotency_key    :string
  #  processing_time_ms :integer
  #  request_payload    :text
  #  response_payload   :text
  #  status             :string           not null
  #  created_at         :datetime         not null
  #  updated_at         :datetime         not null
  #  webhook_endpoint_id :bigint          not null
  #
  # Indexes
  #
  #  index_webhook_logs_on_idempotency_key            (idempotency_key)
  #  index_webhook_logs_on_status                     (status)
  #  index_webhook_logs_on_webhook_endpoint_id        (webhook_endpoint_id)
  #  index_webhook_logs_on_webhook_endpoint_id_and_created_at (webhook_endpoint_id,created_at)
  #
  class WebhookLog < ApplicationRecord
    belongs_to :webhook_endpoint

    # Enums
    enum :status, {
      success: "success",
      failure: "failure",
      invalid_signature: "invalid_signature",
      duplicate: "duplicate"
    }, validate: true

    # Scopes
    scope :recent, -> { order(created_at: :desc).limit(100) }
    scope :successful, -> { where(status: :success) }
    scope :failed, -> { where(status: [:failure, :invalid_signature]) }

    # Truncate large payloads before save
    before_save :truncate_payloads

    # Maximum payload size to store (100KB)
    MAX_PAYLOAD_SIZE = 100_000

    private

    def truncate_payloads
      if request_payload && request_payload.bytesize > MAX_PAYLOAD_SIZE
        self.request_payload = request_payload.truncate(MAX_PAYLOAD_SIZE, omission: "...[truncated]")
      end

      if response_payload && response_payload.bytesize > MAX_PAYLOAD_SIZE
        self.response_payload = response_payload.truncate(MAX_PAYLOAD_SIZE, omission: "...[truncated]")
      end
    end
  end
  ```

- [ ] Add associations to Family model
  ```ruby
  # In app/models/family.rb, add:
  has_many :webhook_endpoints, dependent: :destroy
  ```

- [ ] Run migrations: `bin/rails db:migrate`

- [ ] Create fixture data in `test/fixtures/webhook_endpoints.yml`
  ```yaml
  n8n_telegram:
    family: dylan_family
    name: "Telegram Bot Webhook"
    url: "https://n8n.example.com/webhook/telegram-bot"
    secret_encrypted: "test_secret_abc123"
    enabled: true
    success_count: 15
    last_used_at: <%= 1.day.ago %>

  n8n_recurring:
    family: dylan_family
    name: "Recurring Expenses Webhook"
    url: "https://n8n.example.com/webhook/recurring"
    secret_encrypted: "test_secret_xyz789"
    enabled: false
  ```

- [ ] Write model tests in `test/models/webhook_endpoint_test.rb`
  - Test secret generation on create
  - Test secret regeneration
  - Test soft delete/restore
  - Test HTTPS validation in production
  - Test record_success!/record_failure! updates counts
  - Test active? scope and method

- [ ] Write model tests in `test/models/webhook_log_test.rb`
  - Test payload truncation for large payloads
  - Test status enum
  - Test scopes (recent, successful, failed)

### 4.2 Phase 2: Webhook Security Infrastructure

**Justification:** Implements spec section 3.2 (Webhook Security). HMAC signature verification for secure webhook calls.

**Tasks:**

- [ ] Create webhook signature verifier in `app/models/webhook_signature_verifier.rb`
  ```ruby
  # frozen_string_literal: true

  # HMAC-SHA256 signature verification for n8n webhooks
  #
  # Implements the same signature scheme as Stripe webhooks:
  # - Signature header format: t=<timestamp>,v1=<signature>
  # - Signed payload: <timestamp>.<json_body>
  # - HMAC-SHA256 algorithm
  # - 5-minute timestamp tolerance
  #
  # @example Verify webhook signature
  #   verifier = WebhookSignatureVerifier.new(
  #     secret: webhook_endpoint.secret,
  #     signature_header: request.headers["X-N8N-Signature"],
  #     payload: request.raw_post
  #   )
  #
  #   if verifier.valid?
  #     # Process webhook
  #   else
  #     # Reject webhook
  #     Rails.logger.error("Invalid signature: #{verifier.error}")
  #   end
  #
  class WebhookSignatureVerifier
    # Timestamp tolerance in seconds (5 minutes)
    TIMESTAMP_TOLERANCE = 300

    attr_reader :secret, :signature_header, :payload, :error

    # Initialize signature verifier
    #
    # @param secret [String] Webhook endpoint secret
    # @param signature_header [String] X-N8N-Signature header value
    # @param payload [String] Raw request body (JSON string)
    def initialize(secret:, signature_header:, payload:)
      @secret = secret
      @signature_header = signature_header
      @payload = payload
      @error = nil
    end

    # Verify webhook signature
    #
    # @return [Boolean] True if signature is valid
    def valid?
      return false unless parse_signature_header
      return false unless verify_timestamp
      return false unless verify_signature

      true
    end

    # Get timestamp from signature header
    #
    # @return [Integer, nil] Unix timestamp
    def timestamp
      @timestamp
    end

    private

    # Parse signature header into timestamp and signature
    #
    # Expected format: t=1672531200,v1=5f3e8d2a...
    #
    # @return [Boolean] True if parsed successfully
    def parse_signature_header
      if signature_header.blank?
        @error = "Missing signature header"
        return false
      end

      # Parse header components
      components = signature_header.split(",").each_with_object({}) do |pair, hash|
        key, value = pair.split("=", 2)
        hash[key] = value
      end

      @timestamp = components["t"]&.to_i
      @signature = components["v1"]

      if @timestamp.nil? || @signature.blank?
        @error = "Invalid signature header format"
        return false
      end

      true
    end

    # Verify timestamp is within tolerance
    #
    # @return [Boolean] True if timestamp is valid
    def verify_timestamp
      current_time = Time.current.to_i
      time_diff = (current_time - @timestamp).abs

      if time_diff > TIMESTAMP_TOLERANCE
        @error = "Timestamp outside tolerance (#{time_diff}s > #{TIMESTAMP_TOLERANCE}s)"
        return false
      end

      true
    end

    # Verify HMAC signature
    #
    # @return [Boolean] True if signature matches
    def verify_signature
      expected_signature = calculate_signature

      # Constant-time comparison to prevent timing attacks
      unless Rack::Utils.secure_compare(expected_signature, @signature)
        @error = "Signature mismatch"
        return false
      end

      true
    end

    # Calculate expected HMAC signature
    #
    # @return [String] Hex-encoded HMAC-SHA256 signature
    def calculate_signature
      signed_payload = "#{@timestamp}.#{payload}"
      OpenSSL::HMAC.hexdigest("SHA256", secret, signed_payload)
    end
  end
  ```

- [ ] Add signature generation helper for testing/documentation
  ```ruby
  # In app/models/webhook_endpoint.rb, add:

  # Generate signature header for webhook payload
  #
  # Used for testing and documentation examples.
  #
  # @param payload [String] JSON payload (request body)
  # @param timestamp [Integer] Unix timestamp (default: current time)
  # @return [String] Signature header value
  #
  # @example
  #   webhook.generate_signature_header('{"type":"transaction.create"}')
  #   # => "t=1672531200,v1=5f3e8d2a1b4c9f7e6d3a2b1c0f9e8d7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e"
  #
  def generate_signature_header(payload, timestamp: Time.current.to_i)
    signed_payload = "#{timestamp}.#{payload}"
    signature = OpenSSL::HMAC.hexdigest("SHA256", secret, signed_payload)

    "t=#{timestamp},v1=#{signature}"
  end
  ```

- [ ] Write comprehensive tests in `test/models/webhook_signature_verifier_test.rb`
  ```ruby
  require "test_helper"

  class WebhookSignatureVerifierTest < ActiveSupport::TestCase
    setup do
      @secret = "test_webhook_secret_abc123"
      @payload = '{"type":"transaction.create","data":{"amount":25.50}}'
      @timestamp = Time.current.to_i
    end

    test "verifies valid signature" do
      signature = generate_signature(@payload, @timestamp)
      verifier = WebhookSignatureVerifier.new(
        secret: @secret,
        signature_header: signature,
        payload: @payload
      )

      assert verifier.valid?
      assert_nil verifier.error
    end

    test "rejects missing signature header" do
      verifier = WebhookSignatureVerifier.new(
        secret: @secret,
        signature_header: nil,
        payload: @payload
      )

      assert_not verifier.valid?
      assert_equal "Missing signature header", verifier.error
    end

    test "rejects invalid signature format" do
      verifier = WebhookSignatureVerifier.new(
        secret: @secret,
        signature_header: "invalid_format",
        payload: @payload
      )

      assert_not verifier.valid?
      assert_equal "Invalid signature header format", verifier.error
    end

    test "rejects signature with wrong secret" do
      signature = generate_signature(@payload, @timestamp, secret: "wrong_secret")
      verifier = WebhookSignatureVerifier.new(
        secret: @secret,
        signature_header: signature,
        payload: @payload
      )

      assert_not verifier.valid?
      assert_equal "Signature mismatch", verifier.error
    end

    test "rejects signature with modified payload" do
      signature = generate_signature(@payload, @timestamp)
      modified_payload = '{"type":"transaction.create","data":{"amount":50.00}}'

      verifier = WebhookSignatureVerifier.new(
        secret: @secret,
        signature_header: signature,
        payload: modified_payload
      )

      assert_not verifier.valid?
      assert_equal "Signature mismatch", verifier.error
    end

    test "rejects timestamp outside tolerance" do
      old_timestamp = 1.hour.ago.to_i
      signature = generate_signature(@payload, old_timestamp)

      verifier = WebhookSignatureVerifier.new(
        secret: @secret,
        signature_header: signature,
        payload: @payload
      )

      assert_not verifier.valid?
      assert_match(/Timestamp outside tolerance/, verifier.error)
    end

    test "accepts timestamp within tolerance" do
      recent_timestamp = 2.minutes.ago.to_i
      signature = generate_signature(@payload, recent_timestamp)

      verifier = WebhookSignatureVerifier.new(
        secret: @secret,
        signature_header: signature,
        payload: @payload
      )

      assert verifier.valid?
    end

    test "extracts timestamp from valid signature" do
      signature = generate_signature(@payload, @timestamp)
      verifier = WebhookSignatureVerifier.new(
        secret: @secret,
        signature_header: signature,
        payload: @payload
      )

      verifier.valid?
      assert_equal @timestamp, verifier.timestamp
    end

    private

    def generate_signature(payload, timestamp, secret: @secret)
      signed_payload = "#{timestamp}.#{payload}"
      signature = OpenSSL::HMAC.hexdigest("SHA256", secret, signed_payload)
      "t=#{timestamp},v1=#{signature}"
    end
  end
  ```

### 4.3 Phase 3: n8n Webhook Endpoint

**Justification:** Implements spec section 3.3 (Webhook Payload Format). Core webhook endpoint for receiving data from n8n.

**Tasks:**

- [ ] Create webhooks controller for n8n in `app/controllers/webhooks/n8n_controller.rb`
  ```ruby
  # frozen_string_literal: true

  module Webhooks
    # Controller for n8n webhook integration
    #
    # Handles webhook calls from n8n workflows with signature verification,
    # idempotency support, and transaction creation.
    #
    # Security:
    # - HMAC-SHA256 signature verification required
    # - Rate limiting applied (500 req/hour)
    # - Idempotency keys prevent duplicate processing
    #
    # Supported operations:
    # - transaction.create - Create single transaction
    # - transactions.bulk_create - Create multiple transactions
    #
    class N8nController < ApplicationController
      skip_before_action :verify_authenticity_token
      skip_before_action :authenticate_user!

      before_action :find_webhook_endpoint
      before_action :verify_webhook_signature
      before_action :check_idempotency
      before_action :parse_webhook_payload

      # POST /webhooks/n8n/:webhook_id
      def create
        start_time = Time.current

        result = process_webhook

        log_webhook_call(
          status: :success,
          request_payload: @raw_payload,
          response_payload: result.to_json,
          processing_time_ms: ((Time.current - start_time) * 1000).to_i
        )

        @webhook_endpoint.record_success!

        render json: result, status: :ok
      rescue => e
        log_webhook_call(
          status: :failure,
          request_payload: @raw_payload,
          error_message: e.message,
          processing_time_ms: ((Time.current - start_time) * 1000).to_i
        )

        @webhook_endpoint.record_failure!

        # Return 200 OK even on error (n8n webhook best practice)
        render json: { success: false, error: e.message }, status: :ok
      end

      private

      # Find webhook endpoint by ID in URL
      def find_webhook_endpoint
        @webhook_endpoint = WebhookEndpoint.active.find_by(id: params[:webhook_id])

        unless @webhook_endpoint
          render json: { error: "Webhook endpoint not found or inactive" }, status: :not_found
          return
        end
      end

      # Verify HMAC signature
      def verify_webhook_signature
        @raw_payload = request.raw_post
        signature_header = request.headers["X-N8N-Signature"]

        verifier = WebhookSignatureVerifier.new(
          secret: @webhook_endpoint.secret,
          signature_header: signature_header,
          payload: @raw_payload
        )

        unless verifier.valid?
          log_webhook_call(
            status: :invalid_signature,
            request_payload: @raw_payload,
            error_message: verifier.error
          )

          render json: { error: "Invalid signature: #{verifier.error}" }, status: :unauthorized
          return
        end
      end

      # Check idempotency key to prevent duplicate processing
      def check_idempotency
        @payload = JSON.parse(@raw_payload)
        idempotency_key = @payload["idempotency_key"]

        return unless idempotency_key.present?

        # Check if we've processed this key before (last 24 hours)
        existing_log = @webhook_endpoint.webhook_logs
          .where(idempotency_key: idempotency_key)
          .where("created_at > ?", 24.hours.ago)
          .where(status: :success)
          .first

        if existing_log
          log_webhook_call(
            status: :duplicate,
            request_payload: @raw_payload,
            idempotency_key: idempotency_key
          )

          # Return original response
          render json: JSON.parse(existing_log.response_payload), status: :ok
          return
        end
      end

      # Parse and validate webhook payload
      def parse_webhook_payload
        # Already parsed in check_idempotency
        @webhook_type = @payload["type"]

        unless @webhook_type.present?
          raise ArgumentError, "Missing 'type' field in payload"
        end
      end

      # Process webhook based on type
      def process_webhook
        case @webhook_type
        when "transaction.create"
          process_single_transaction
        when "transactions.bulk_create"
          process_bulk_transactions
        else
          raise ArgumentError, "Unknown webhook type: #{@webhook_type}"
        end
      end

      # Process single transaction creation
      def process_single_transaction
        data = @payload["data"]
        transaction = create_transaction_from_webhook(data)

        {
          success: true,
          transaction: format_transaction_response(transaction)
        }
      end

      # Process bulk transaction creation
      # (Implementation in Phase 4)
      def process_bulk_transactions
        raise NotImplementedError, "Bulk transactions will be implemented in Phase 4"
      end

      # Create transaction from webhook data
      #
      # Supports name-based lookups for account, category, merchant
      def create_transaction_from_webhook(data)
        family = @webhook_endpoint.family

        # Resolve account (by name or ID)
        account = resolve_account(data["account"], family)

        # Resolve category (by name or ID, optional)
        category = resolve_category(data["category"], family) if data["category"]

        # Resolve or create merchant (optional)
        merchant = resolve_or_create_merchant(data["merchant"], family) if data["merchant"]

        # Parse amount and nature
        amount = parse_amount(data["amount"], data["nature"])

        # Create transaction via API
        transaction = Transaction.create!(
          account: account,
          amount: Money.new((amount * 100).to_i, family.currency),
          date: data["date"] || Date.current,
          name: data["description"] || data["name"],
          notes: data["notes"],
          category: category,
          merchant: merchant,
          kind: :standard
        )

        # Add tags if provided
        if data["tags"].present?
          tags = resolve_tags(data["tags"], family)
          transaction.update!(tags: tags)
        end

        # Sync account asynchronously
        account.sync_later

        transaction
      end

      # Resolve account by name or ID
      def resolve_account(identifier, family)
        return nil if identifier.blank?

        # Try UUID first
        account = family.accounts.find_by(id: identifier)
        return account if account

        # Try name lookup (case-insensitive)
        account = family.accounts.find_by("LOWER(name) = ?", identifier.to_s.downcase)

        unless account
          raise ArgumentError, "Account not found: #{identifier}"
        end

        account
      end

      # Resolve category by name or ID
      def resolve_category(identifier, family)
        return nil if identifier.blank?

        # Try UUID first
        category = family.categories.find_by(id: identifier)
        return category if category

        # Try exact name match (case-insensitive)
        category = family.categories.find_by("LOWER(name) = ?", identifier.to_s.downcase)
        return category if category

        # Try fuzzy match (contains)
        category = family.categories.where("LOWER(name) LIKE ?", "%#{identifier.to_s.downcase}%").first

        category
      end

      # Resolve or create merchant
      def resolve_or_create_merchant(identifier, family)
        return nil if identifier.blank?

        # Try UUID first
        merchant = Merchant.find_by(id: identifier)
        return merchant if merchant

        # Try exact name match
        merchant = family.merchants.find_by("LOWER(name) = ?", identifier.to_s.downcase)
        return merchant if merchant

        # Create new family merchant
        FamilyMerchant.create!(
          family: family,
          name: identifier
        )
      end

      # Resolve tags by names or IDs
      def resolve_tags(tag_identifiers, family)
        return [] if tag_identifiers.blank?

        tag_identifiers.map do |identifier|
          # Try UUID first
          tag = family.tags.find_by(id: identifier)
          next tag if tag

          # Try name match
          family.tags.find_by("LOWER(name) = ?", identifier.to_s.downcase)
        end.compact
      end

      # Parse amount and apply nature (income/expense)
      def parse_amount(amount_value, nature)
        amount = amount_value.to_f

        # Determine sign based on nature
        if nature == "income" || nature == "inflow"
          -amount.abs  # Income is negative
        elsif nature == "expense" || nature == "outflow"
          amount.abs   # Expense is positive
        else
          # Infer from amount sign if nature not specified
          amount
        end
      end

      # Format transaction for response
      def format_transaction_response(transaction)
        {
          id: transaction.id,
          account_id: transaction.account_id,
          amount: transaction.amount.format,
          date: transaction.date.iso8601,
          description: transaction.name,
          category: transaction.category ? {
            id: transaction.category.id,
            name: transaction.category.name
          } : nil,
          merchant: transaction.merchant ? {
            id: transaction.merchant.id,
            name: transaction.merchant.name
          } : nil
        }
      end

      # Log webhook call to database
      def log_webhook_call(status:, request_payload:, response_payload: nil, error_message: nil, processing_time_ms: nil)
        @webhook_endpoint.webhook_logs.create!(
          status: status,
          request_payload: request_payload,
          response_payload: response_payload,
          error_message: error_message,
          processing_time_ms: processing_time_ms,
          idempotency_key: @payload&.dig("idempotency_key")
        )
      end
    end
  end
  ```

- [ ] Add route in `config/routes.rb`
  ```ruby
  # Add to webhooks namespace
  namespace :webhooks do
    post "n8n/:webhook_id", to: "n8n#create", as: :n8n
  end
  ```

- [ ] Write controller tests in `test/controllers/webhooks/n8n_controller_test.rb`
  - Test valid webhook with signature
  - Test invalid signature rejection
  - Test missing webhook endpoint
  - Test idempotency key prevents duplicates
  - Test account/category/merchant resolution
  - Test transaction creation
  - Test error handling
  - Follow existing webhook controller test patterns

### 4.4 Phase 4: Bulk Transaction Support

**Justification:** Implements spec section 3.3 (Webhook Payload Format - Bulk). Allow creating multiple transactions in one webhook call.

**Tasks:**

- [ ] Implement bulk transaction processing in `app/controllers/webhooks/n8n_controller.rb`
  ```ruby
  # Add to N8nController

  # Process bulk transaction creation
  #
  # Creates multiple transactions from array of transaction data.
  # Each transaction processed independently - partial success possible.
  #
  # @return [Hash] Results with success/failure summary
  def process_bulk_transactions
    transactions_data = @payload["transactions"]

    unless transactions_data.is_a?(Array)
      raise ArgumentError, "transactions must be an array"
    end

    if transactions_data.size > 100
      raise ArgumentError, "Maximum 100 transactions per bulk request"
    end

    results = transactions_data.map.with_index do |data, index|
      begin
        transaction = create_transaction_from_webhook(data)

        {
          success: true,
          index: index,
          transaction: format_transaction_response(transaction)
        }
      rescue => e
        {
          success: false,
          index: index,
          error: e.message,
          data: data
        }
      end
    end

    successful = results.count { |r| r[:success] }
    failed = results.count { |r| !r[:success] }

    {
      success: failed == 0,  # Only true if all succeeded
      results: results,
      summary: {
        total: transactions_data.size,
        successful: successful,
        failed: failed
      }
    }
  end
  ```

- [ ] Add bulk transaction support to tests
  - Test bulk creation with all successful
  - Test bulk creation with partial failures
  - Test bulk creation exceeds limit (100 transactions)
  - Test bulk idempotency
  - Test performance with 50 transactions

### 4.5 Phase 5: Convenience API Endpoints

**Justification:** Implements spec section 3.4 (API Enhancements). Helper endpoints for easier n8n workflow building.

**Tasks:**

- [ ] Add account lookup endpoint in `app/controllers/api/v1/accounts_controller.rb`
  ```ruby
  # Add to existing AccountsController

  # GET /api/v1/accounts/lookup
  #
  # Find account by name (case-insensitive, optional fuzzy matching)
  #
  # Parameters:
  # - name: Account name to search for (required)
  # - exact: Require exact match (optional, default: false)
  #
  # Returns: Account object or 404 not found
  def lookup
    authorize_scope!(:read)

    name = params[:name]
    exact = params[:exact] == "true"

    if name.blank?
      render json: { error: "name parameter required" }, status: :bad_request
      return
    end

    account = if exact
      Current.family.accounts.find_by("LOWER(name) = ?", name.downcase)
    else
      # Fuzzy match (contains)
      Current.family.accounts.where("LOWER(name) LIKE ?", "%#{name.downcase}%").first
    end

    if account
      render "show", locals: { account: account }
    else
      render json: { error: "not_found", message: "No account found with name: #{name}" }, status: :not_found
    end
  end
  ```

- [ ] Add category lookup endpoint in `app/controllers/api/v1/categories_controller.rb`
  ```ruby
  # Add to existing CategoriesController

  # GET /api/v1/categories/lookup
  #
  # Find category by name with fuzzy matching
  #
  # Parameters:
  # - name: Category name to search for (required)
  # - fuzzy: Allow fuzzy matching (optional, default: true)
  #
  # Returns: Category object or 404 not found
  def lookup
    authorize_scope!(:read)

    name = params[:name]
    fuzzy = params[:fuzzy] != "false"  # Default true

    if name.blank?
      render json: { error: "name parameter required" }, status: :bad_request
      return
    end

    category = find_category_by_name(name, fuzzy: fuzzy)

    if category
      render "show", locals: { category: category }
    else
      render json: { error: "not_found", message: "No category found with name: #{name}" }, status: :not_found
    end
  end

  private

  def find_category_by_name(name, fuzzy: true)
    # Try exact match first
    category = Current.family.categories.find_by("LOWER(name) = ?", name.downcase)
    return category if category || !fuzzy

    # Try contains match
    category = Current.family.categories.where("LOWER(name) LIKE ?", "%#{name.downcase}%").first
    return category if category

    # Try common aliases/shortcuts
    category_aliases = {
      "food" => "Food & Drink",
      "gas" => "Gas & Fuel",
      "restaurant" => "Food & Drink",
      "coffee" => "Food & Drink",
      "grocery" => "Groceries",
      "transport" => "Transportation"
    }

    alias_match = category_aliases[name.downcase]
    if alias_match
      Current.family.categories.find_by("LOWER(name) = ?", alias_match.downcase)
    end
  end
  ```

- [ ] Create merchants helper controller in `app/controllers/api/v1/merchants_controller.rb`
  ```ruby
  # frozen_string_literal: true

  module Api
    module V1
      # Merchants API endpoint for n8n integration
      class MerchantsController < BaseController
        # POST /api/v1/merchants/find_or_create
        #
        # Find existing merchant or create new one
        #
        # Parameters:
        # - name: Merchant name (required)
        # - create_if_missing: Create if not found (default: true)
        #
        # Returns: Merchant object with 'created' flag
        def find_or_create
          authorize_scope!(:write)

          name = params[:name]
          create_if_missing = params[:create_if_missing] != "false"

          if name.blank?
            render json: { error: "name parameter required" }, status: :bad_request
            return
          end

          # Try to find existing merchant (case-insensitive)
          merchant = Current.family.merchants.find_by("LOWER(name) = ?", name.downcase)

          if merchant
            render json: {
              merchant: format_merchant(merchant),
              created: false
            }
            return
          end

          # Create new merchant if allowed
          unless create_if_missing
            render json: { error: "not_found", message: "Merchant not found: #{name}" }, status: :not_found
            return
          end

          merchant = FamilyMerchant.create!(
            family: Current.family,
            name: name
          )

          render json: {
            merchant: format_merchant(merchant),
            created: true
          }, status: :created
        end

        private

        def format_merchant(merchant)
          {
            id: merchant.id,
            name: merchant.name,
            type: merchant.type
          }
        end
      end
    end
  end
  ```

- [ ] Add routes in `config/routes.rb`
  ```ruby
  # Add to api/v1 namespace
  namespace :api do
    namespace :v1 do
      resources :accounts do
        collection do
          get :lookup
        end
      end

      resources :categories do
        collection do
          get :lookup
        end
      end

      resources :merchants, only: [] do
        collection do
          post :find_or_create
        end
      end
    end
  end
  ```

- [ ] Write controller tests for new endpoints
  - Test account lookup (exact and fuzzy)
  - Test category lookup with alias support
  - Test merchant find_or_create
  - Test authorization (requires read/write scopes)

### 4.6 Phase 6: Settings UI for Webhook Management

**Justification:** Implements spec section 3.5 (UI Components). User-friendly interface for webhook configuration.

**Tasks:**

- [ ] Create webhooks settings controller in `app/controllers/settings/webhooks_controller.rb`
  ```ruby
  # Follow pattern from other settings controllers
  # Implement standard CRUD actions: index, new, create, edit, update, destroy
  # Add custom actions: test, regenerate_secret
  ```

- [ ] Add routes in `config/routes.rb`
  ```ruby
  namespace :settings do
    resources :webhooks do
      member do
        post :test
        post :regenerate_secret
      end

      resources :logs, only: [:index], controller: "webhook_logs"
    end
  end
  ```

- [ ] Create index view in `app/views/settings/webhooks/index.html.erb`
  ```erb
  <div class="webhooks-settings-page">
    <div class="page-header mb-6 flex items-center justify-between">
      <div>
        <h1 class="text-2xl font-bold text-primary">
          <%= t(".heading") %>
        </h1>
        <p class="text-sm text-tertiary">
          <%= t(".description") %>
        </p>
      </div>

      <%= link_to t(".new_webhook"),
                  new_settings_webhook_path,
                  class: "btn btn-primary" %>
    </div>

    <% if @webhooks.any? %>
      <div class="webhooks-table">
        <table class="w-full">
          <thead>
            <tr class="border-b border-primary">
              <th class="p-3 text-left"><%= t(".name") %></th>
              <th class="p-3 text-left"><%= t(".url") %></th>
              <th class="p-3 text-left"><%= t(".status") %></th>
              <th class="p-3 text-left"><%= t(".usage") %></th>
              <th class="p-3 text-left"><%= t(".last_used") %></th>
              <th class="p-3 text-right"><%= t(".actions") %></th>
            </tr>
          </thead>
          <tbody>
            <% @webhooks.each do |webhook| %>
              <tr class="border-b border-primary hover:bg-surface-inset">
                <td class="p-3">
                  <div class="font-medium text-primary">
                    <%= webhook.name %>
                  </div>
                </td>

                <td class="p-3 font-mono text-xs text-tertiary">
                  <%= truncate(webhook.url, length: 40) %>
                </td>

                <td class="p-3">
                  <% if webhook.enabled? %>
                    <span class="badge badge-success">
                      <%= t(".active") %>
                    </span>
                  <% else %>
                    <span class="badge badge-warning">
                      <%= t(".inactive") %>
                    </span>
                  <% end %>
                </td>

                <td class="p-3 text-sm">
                  <div class="text-success">
                    <%= icon("check", class: "w-3 h-3 inline") %>
                    <%= webhook.success_count %>
                  </div>
                  <div class="text-destructive">
                    <%= icon("x", class: "w-3 h-3 inline") %>
                    <%= webhook.failure_count %>
                  </div>
                </td>

                <td class="p-3 text-sm text-tertiary">
                  <%= webhook.last_used_at ? time_ago_in_words(webhook.last_used_at) + " ago" : t(".never") %>
                </td>

                <td class="p-3 text-right">
                  <div class="flex items-center justify-end gap-2">
                    <%= link_to t(".test"),
                                test_settings_webhook_path(webhook),
                                method: :post,
                                class: "text-xs text-link hover:underline" %>

                    <%= link_to t(".edit"),
                                edit_settings_webhook_path(webhook),
                                class: "text-xs text-link hover:underline" %>

                    <%= link_to t(".logs"),
                                settings_webhook_logs_path(webhook),
                                class: "text-xs text-link hover:underline" %>

                    <%= link_to t(".delete"),
                                settings_webhook_path(webhook),
                                method: :delete,
                                data: { confirm: t(".delete_confirm") },
                                class: "text-xs text-destructive hover:underline" %>
                  </div>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    <% else %>
      <%= render "empty_state" %>
    <% end %>
  </div>
  ```

- [ ] Create form partial in `app/views/settings/webhooks/_form.html.erb`
  - Name field (text input)
  - URL field (URL input with https validation)
  - Enabled checkbox
  - Secret display (masked with show/copy buttons)
  - Save/Cancel buttons
  - Follow existing settings form patterns

- [ ] Create webhook secret display component
  - Masked by default: `••••••••••••••••••••••••••••`
  - "Show" button reveals full secret
  - "Copy to Clipboard" button
  - "Regenerate Secret" button (with confirmation)

- [ ] Create test webhook modal/action
  - Generate test payload
  - Send POST to webhook URL with signature
  - Display response (success/failure)
  - Show curl example for manual testing

- [ ] Create webhook logs view in `app/views/settings/webhook_logs/index.html.erb`
  - Table of recent logs (last 100)
  - Filters: status, date range
  - Expandable rows with full payload
  - Follow existing log/history table patterns

- [ ] Add localization in `config/locales/views/settings/webhooks.en.yml`
  - All user-facing strings
  - Form labels, buttons, help text
  - Success/error messages

- [ ] Add navigation link to webhooks settings
  - Add link in settings sidebar or menu
  - Follow existing settings navigation pattern

### 4.7 Phase 7: Comprehensive Documentation

**Justification:** Implements spec section FR-7 (Documentation). Developer documentation in all requested formats.

**Tasks:**

- [ ] Create n8n integration guide in `docs/integrations/n8n.md`
  ```markdown
  # n8n Integration Guide

  ## Overview
  This guide explains how to integrate Sure with n8n for workflow automation.

  ## Quick Start

  ### 1. Create Webhook Endpoint
  1. Navigate to Settings > Webhooks
  2. Click "New Webhook"
  3. Enter name (e.g., "Telegram Bot")
  4. Enter your n8n webhook URL
  5. Copy the webhook secret

  ### 2. Configure n8n Workflow
  [Step-by-step with screenshots]

  ### 3. Test Integration
  [Test payload and verification]

  ## Example Workflows

  ### Telegram → n8n → Sure
  [Complete workflow with code]

  ### Recurring Expense Tracking
  [Scheduled workflow example]

  ### Receipt Parsing with OCR
  [Advanced workflow with image processing]

  ## API Reference

  ### Webhook Endpoint
  POST /webhooks/n8n/:webhook_id

  ### Signature Verification
  [HMAC-SHA256 details and examples]

  ### Payload Formats
  [Single and bulk transaction examples]

  ## Troubleshooting
  [Common issues and solutions]
  ```

- [ ] Create Postman collection in `docs/postman/n8n-integration.json`
  - Collection with all n8n-related endpoints
  - Pre-request scripts for signature generation
  - Environment variables for webhook ID, secret, base URL
  - Example requests with sample payloads
  - Follow existing Postman collection patterns

- [ ] Update OpenAPI spec in `docs/api/openapi.yaml`
  - Add webhook endpoint definition
  - Add convenience endpoint definitions (lookup, find_or_create)
  - Add request/response schemas
  - Add security scheme for X-N8N-Signature header
  - Follow existing OpenAPI patterns in codebase

- [ ] Create code examples directory `docs/examples/n8n/`
  - `telegram-bot.js` - n8n JavaScript for Telegram integration
  - `signature-verification.py` - Python example for webhook signature
  - `bulk-import.sh` - cURL script for bulk transaction import
  - Each file with detailed comments

- [ ] Add n8n section to main API docs in `docs/api/README.md`
  - Link to n8n integration guide
  - Quick reference for webhook endpoints
  - Link to Postman collection

### 4.8 Phase 8: Testing & Validation

**Justification:** Comprehensive validation of all n8n integration components.

**Tasks:**

- [ ] Write integration test in `test/integration/n8n_webhook_flow_test.rb`
  - Test complete flow: create webhook → send signed payload → verify transaction created
  - Test idempotency: send same payload twice → only one transaction created
  - Test bulk transactions: send 10 transactions → all created
  - Test error handling: invalid signature → logged and rejected

- [ ] Write system test in `test/system/webhook_management_test.rb`
  - Test creating webhook via UI
  - Test viewing webhook secret
  - Test regenerating webhook secret
  - Test viewing webhook logs
  - Test deleting webhook

- [ ] Performance testing
  - Load test webhook endpoint (100 requests/minute)
  - Benchmark bulk transaction creation (50 transactions)
  - Verify rate limiting works correctly
  - Test under Redis failure (graceful degradation)

- [ ] Security testing
  - Verify signature rejection for tampered payloads
  - Verify timestamp validation prevents replay attacks
  - Verify secrets are encrypted in database
  - Verify secrets not exposed in logs or error messages

- [ ] Run full test suite: `bin/rails test`
- [ ] Run system tests: `bin/rails test:system`
- [ ] Run linting: `bin/rubocop -f github -a`
- [ ] Run security scan: `bin/brakeman --no-pager`

- [ ] Create webhook cleanup job in `app/jobs/cleanup_webhook_logs_job.rb`
  ```ruby
  # Periodic job to delete old webhook logs (30+ days)
  class CleanupWebhookLogsJob < ApplicationJob
    queue_as :scheduled

    def perform
      deleted_count = WebhookLog.where("created_at < ?", 30.days.ago).delete_all
      Rails.logger.info("Deleted #{deleted_count} webhook logs older than 30 days")
    end
  end
  ```

- [ ] Add to sidekiq-cron schedule in `config/schedule.yml`
  ```yaml
  cleanup_webhook_logs:
    cron: "0 4 * * *"  # 4:00 AM daily
    class: "CleanupWebhookLogsJob"
    queue: "scheduled"
  ```

- [ ] Manual end-to-end validation
  - Create actual n8n workflow with Telegram
  - Send message via Telegram bot
  - Verify transaction appears in Sure
  - Test with various formats (different amounts, categories, etc.)
  - Document any issues or improvements needed

---

## Additional Considerations

### Rate Limiting for Webhooks
- Consider separate rate limit tier for webhooks (500/hour vs 100/hour for regular API)
- In self-hosted mode, no limits (user controls infrastructure)
- Track webhook-specific rate limiting separately from API keys

### CORS Configuration
- If n8n workflows run in browser (unlikely), may need CORS headers
- For now, assume server-to-server communication (no CORS needed)
- Can add later if needed: `rack-cors` gem

### Webhook Retries
- n8n has built-in retry mechanism
- Idempotency keys prevent duplicate transactions on retry
- Return 200 OK even on failure (n8n best practice)
- Log all attempts for debugging

### Custom n8n Node (Future Enhancement)
- Build official Sure community node for n8n
- Simplifies configuration (no manual webhooks/signatures)
- OAuth integration for easier auth
- Pre-built actions (create transaction, list categories, etc.)
- Separate repository/package, outside current scope

### Multi-Webhook Support
- Users can create multiple webhooks for different workflows
- Each webhook has own secret (per-endpoint security)
- Can disable/delete webhooks independently
- Useful for separating Telegram, recurring expenses, receipt parsing, etc.

### Webhook URL Validation
- HTTPS required in production (security best practice)
- Allow HTTP in development/test for local n8n instances
- URL format validation prevents common errors

### Error Messages
- Clear, actionable error messages for failed webhooks
- Logged to webhook_logs for debugging
- Not exposed in webhook response (security)
- Sentry integration for critical errors

### Data Privacy
- Webhook payloads may contain sensitive financial data
- Encrypted in transit (HTTPS)
- Stored in webhook_logs for 30 days (debugging)
- Automatically deleted after retention period
- Excluded from backups if needed

---

**End of Implementation Plan**
