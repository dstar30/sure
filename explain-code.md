# Sure - Personal Finance Application Architecture

**A Comprehensive Guide to the Codebase**

---

## Table of Contents

1. [Overview](#overview)
2. [Application Architecture](#application-architecture)
3. [Core Domain Model](#core-domain-model)
4. [Key Features](#key-features)
5. [Frontend Architecture](#frontend-architecture)
6. [Background Processing](#background-processing)
7. [Authentication & Authorization](#authentication--authorization)
8. [API Structure](#api-structure)
9. [Data Sync & Import](#data-sync--import)
10. [Testing Approach](#testing-approach)
11. [Directory Structure](#directory-structure)
12. [Design Patterns & Conventions](#design-patterns--conventions)

---

## Overview

Sure is a full-stack personal finance and wealth management application built with Ruby on Rails 7.2. It provides comprehensive financial tracking, budgeting, investment monitoring, and AI-powered financial insights.

### Key Characteristics

- **Technology Stack:** Ruby 3.4.7, Rails 7.2.2, PostgreSQL 9.3+, Redis 5.4+
- **Deployment Modes:** Managed SaaS or Self-Hosted (Docker Compose)
- **Frontend:** Hotwire (Turbo + Stimulus), ViewComponents, Tailwind CSS v4
- **Background Jobs:** Sidekiq with cron scheduling
- **Multi-tenant:** Family-scoped data isolation

---

## Application Architecture

### Deployment Modes

The application runs in two distinct modes controlled by `Rails.application.config.app_mode`:

1. **Managed Mode**: A team operates servers for users (traditional SaaS)
2. **Self-Hosted Mode**: Users run on their own infrastructure via Docker Compose

### Architectural Philosophy

**Skinny Controllers, Fat Models**
- Business logic lives in `app/models/`, not `app/services/`
- Controllers handle HTTP concerns only
- Models answer questions about themselves (e.g., `account.balance_series` not `AccountSeries.new(account).call`)

**Hotwire-First Frontend**
- Native HTML preferred over JavaScript components
- Turbo Frames for partial page updates
- Query params for state management over localStorage
- Server-side formatting for currencies, numbers, dates

**Minimize Dependencies**
- Push Rails to its limits before adding new gems
- Favor old and reliable over new and flashy
- Strong technical/business justification required for new dependencies

---

## Core Domain Model

### Entity Hierarchy

```
Family (multi-tenant boundary)
├── Users (members with roles: member, admin, super_admin)
├── Accounts (polymorphic via accountable)
│   ├── Depository (checking, savings)
│   ├── Investment (brokerage)
│   ├── CreditCard
│   ├── Loan
│   ├── Property
│   ├── Vehicle
│   ├── Crypto
│   ├── OtherAsset
│   └── OtherLiability
├── Entries (polymorphic via entryable)
│   ├── Transaction (income/expense)
│   ├── Trade (buy/sell securities)
│   └── Valuation (balance snapshots)
├── Categories (income/expense classification)
├── Tags (transaction labeling)
├── Merchants (transaction counterparties)
├── Rules (automation engine)
├── Budgets → BudgetCategories
└── RecurringTransactions (pattern detection)
```

### Key Models

#### Account (`app/models/account.rb`)
- **Polymorphism:** Uses `delegated_type` pattern with `accountable`
- **Balance Types:** cash, non_cash, investment
- **State Machine:** active, draft, disabled, pending_deletion
- **Classification:** Virtual column computed in DB (asset/liability)
- **Multi-currency:** Supports currency conversion with historical rates
- **Providers:** Plaid, SimpleFin, Lunchflow, EnableBanking

#### Entry (`app/models/entry.rb`)
- **Polymorphic Parent:** For Transaction, Trade, Valuation
- **External Tracking:** `external_id` and `source` for provider integration
- **Locked Attributes:** JSONB field preventing overwrites from providers
- **Chronological Scopes:** With special valuation ordering
- **Date Constraints:** Minimum supported date is 30 years ago

#### Transaction (`app/models/transaction.rb`)
- **Kinds:** standard, funds_movement, cc_payment, loan_payment, one_time
- **Pending Status:** Tracked in `extra` JSONB field (provider-specific)
- **Associations:** category, merchant, tags
- **Transfer System:** Detection and matching for account-to-account transfers
- **Rules Engine:** Automated categorization and tagging via Ruleable concern

#### Family (`app/models/family.rb`)
- **Multi-tenancy:** All data scoped to family
- **Settings:** currency, locale, date_format, timezone, country
- **Provider Connections:** Manages Plaid, SimpleFin, Lunchflow, EnableBanking
- **Cache Invalidation:** Cache keys with sync timestamps
- **Entry Cache Version:** For optimizing aggregation queries

#### User (`app/models/user.rb`)
- **Roles:** member, admin, super_admin
- **MFA Support:** TOTP with backup codes
- **Preferences:** Stored in JSONB (dashboard sections, reports)
- **OIDC Support:** Link multiple identity providers
- **Email Confirmation:** Workflow (skippable in self-hosted mode)

---

## Key Features

### Financial Data Tracking

**Multi-Account Support**
- Cash accounts (checking, savings)
- Investment accounts with holdings and cost basis
- Credit cards with available credit tracking
- Loans with amortization schedules
- Properties with address and valuation history
- Vehicles, crypto, and other assets/liabilities

**Multi-Currency**
- All monetary values stored with currency
- Historical exchange rates for accurate reporting
- Money gem for currency handling
- Provider-agnostic exchange rate fetching

### Sync & Import System

**Provider Integrations**
- **Plaid:** US/EU banking with OAuth flow
- **SimpleFin:** Open banking with FX metadata
- **Lunchflow:** Custom integration with API key auth
- **EnableBanking:** EU PSD2 compliance

**Import Capabilities**
- CSV import with intelligent column mapping
- Number format detection (US, EU, French, Japanese)
- Date format customization
- Dry run preview before publishing
- Revert capability for failed imports
- Template system for recurring imports

### Transaction Management

**Core Operations**
- Bulk update and delete
- Transfer matching and rejection
- Category assignment with hierarchy
- Merchant detection and enrichment
- Tag-based organization
- Pending transaction support (provider-dependent)

**Automation**
- Rules engine with compound conditions
- Actions: set_category, set_merchant, add_tags, etc.
- Attribute locking to prevent overwrites
- Async job processing for bulk rule runs

### Recurring Transaction Detection

- Automatic pattern identification
- Manual recurring creation from transactions
- Amount variance tracking (min/max/avg)
- Projected transaction display
- Cleanup of stale patterns

### Budgeting

- Monthly budgets with category allocations
- Expected income tracking
- Budget vs. actual comparison
- Multi-currency support

### Reporting & Analytics

**Financial Statements**
- Balance Sheet (assets/liabilities/net worth)
- Income Statement (income/expense analysis)
- Time series analysis with trend calculations

**Visualizations**
- Time series charts (D3.js)
- Donut charts (category breakdown)
- Sankey diagrams (cash flow visualization)
- Aggressive caching for performance

### AI Assistant

- Chat interface with function calling
- OpenAI integration (configurable)
- Function tools: transactions, accounts, balance sheet, income statement
- Streaming responses via Turbo
- Usage tracking per family

---

## Frontend Architecture

### Hotwire Stack

**Turbo Frames**
- Partial page updates without JavaScript
- Used for account lists, transaction tables, settings pages

**Turbo Streams**
- Real-time DOM updates
- WebSocket support via ActionCable
- Server-pushed updates for syncs and imports

**Stimulus Controllers**
- Progressive enhancement philosophy
- 51 controllers across the application
- Co-located with ViewComponents

### Design System

**Tailwind CSS v4**
- Custom design system in `app/assets/tailwind/maybe-design-system.css`
- Functional tokens: `text-primary`, `bg-container`, `border-primary`
- Never create new styles without permission
- Always use semantic tokens, not raw colors

**Semantic HTML First**
- Native `<dialog>` for modals
- `<details><summary>` for disclosures
- Progressive enhancement approach

### ViewComponents Architecture

**Design System Components (`app/components/DS/`)**
- `DS::Button` - Button variants (primary, secondary, ghost, icon)
- `DS::Dialog` - Modal dialogs using native element
- `DS::Menu` - Dropdown menus with keyboard navigation
- `DS::Tabs` - Tab interfaces
- `DS::Alert` - Alert messages
- `DS::Toggle` - Toggle switches

**UI Components (`app/components/UI/`)**
- Application-specific reusable components
- Component-specific Stimulus controllers co-located
- Lookbook for component development (`/design-system`)

**Component Guidelines**
- Prefer components over partials for reusable elements
- Keep domain logic OUT of view templates
- Logic belongs in component Ruby files, not ERB

### Stimulus Controllers

**Key Controllers**
- Chart controllers: `time_series_chart`, `donut_chart`, `sankey_chart`
- Form controllers: `auto_submit_form`, `bulk_select`, `category`, `import`
- UI controllers: `dashboard_sortable`, `theme`, `tooltip`, `clipboard`
- Provider controllers: `plaid`, `lunchflow_preload`

**Best Practices**
- Declarative actions in HTML data attributes
- Keep controllers lightweight (< 7 targets)
- Single responsibility principle
- Pass data via `data-*-value` attributes
- Global controllers in `app/javascript/controllers/`
- Component controllers co-located with components

---

## Background Processing

### Sidekiq Configuration

**Queue Priorities**
- `scheduled` (priority 10)
- `high_priority` (priority 4)
- `medium_priority` (priority 2)
- `low_priority` (priority 1)
- `default` (priority 1)

**Concurrency:** ENV["RAILS_MAX_THREADS"] (default 3)

### Key Background Jobs

**Sync & Import**
- `SyncJob` - Orchestrates account/provider syncs
- `ImportJob` - Processes CSV imports
- `SimplefinHoldingsApplyJob` - Processes SimpleFin holdings

**Automation**
- `RuleJob` - Applies rules to transactions
- `AutoCategorizeJob` - Auto-categorizes transactions
- `AutoDetectMerchantsJob` - Detects merchants from transaction names
- `IdentifyRecurringTransactionsJob` - Identifies recurring patterns

**Market Data**
- `ImportMarketDataJob` - Fetches security prices
- `SecurityHealthCheckJob` - Checks security data availability

**AI Assistant**
- `AssistantResponseJob` - Generates AI chat responses

**Maintenance**
- `DestroyJob` - Defers resource destruction
- `SyncCleanerJob` - Marks stale syncs
- `UserPurgeJob` - Purges deactivated users

### Scheduled Jobs (Cron)

- Daily market data sync
- Stale sync cleanup
- Security health checks
- Recurring transaction identification

---

## Authentication & Authorization

### Authentication

**Session-Based Auth**
- Stored in database (not cookies)
- Password authentication with bcrypt
- Email confirmation workflow
- Password reset with time-limited tokens

**OIDC/OAuth Support**
- Google, GitHub, custom providers
- Identity linking to existing users
- Managed via OmniAuth

**Multi-Factor Authentication**
- TOTP (Time-based One-Time Password)
- Backup codes for recovery
- Optional per user

### Authorization

**Role-Based Access**
- `member` - Standard access
- `admin` - Family management
- `super_admin` - Platform administration

**Multi-Tenancy**
- All data scoped to family
- `Current.family` for scoping
- Impersonation sessions for support

**API Authentication**
- OAuth2 via Doorkeeper
- API keys with JWT tokens
- Scoped permissions (e.g., `accounts:read`, `transactions:write`)
- Rate limiting via Rack Attack

---

## API Structure

### Internal API

- Controllers serve JSON via Turbo
- Jbuilder templates for JSON rendering
- Used for SPA-like interactions

### External API (`/api/v1/`)

**Authentication Endpoints**
- `POST /api/v1/auth/login` - Login with credentials
- `POST /api/v1/auth/signup` - User registration
- `POST /api/v1/auth/refresh` - Token refresh

**Resource Endpoints**
- Accounts: CRUD operations
- Categories: CRUD operations
- Transactions: CRUD operations with filtering
- Chats/Messages: AI assistant interactions
- Sync: Trigger account syncs
- Usage: API usage tracking

**Rate Limiting**
- Rack Attack middleware
- Configurable limits per API key
- NoopApiRateLimiter for testing

**Design Principles**
- RESTful conventions
- Family-based data scoping
- Standardized error responses
- Scope validation on all endpoints

---

## Data Sync & Import

### Provider Integrations

#### Plaid (US/EU Banking)

**Flow:**
1. `PlaidItem` - OAuth connection to bank
2. `PlaidAccount` - Individual accounts at institution
3. `AccountProvider` - Links to Sure `Account`

**Features:**
- Transactions, balances, investments, liabilities
- Webhook processing for real-time updates
- Link token generation for OAuth flow
- Cursor-based pagination for transaction history
- ActiveRecord encryption for access tokens

#### SimpleFin (Open Banking)

**Flow:**
1. `SimplefinItem` - Connection to institution
2. `SimplefinAccount` - Individual accounts
3. `AccountProvider` - Links to Sure `Account`

**Features:**
- Transactions, balances, holdings
- Pending transaction support (configurable via `SIMPLEFIN_INCLUDE_PENDING`)
- FX metadata tracking in `extra` JSONB
- Investment holdings with cost basis
- Raw payload debugging (configurable via `SIMPLEFIN_DEBUG_RAW`)

#### Lunchflow (Custom Integration)

- API key-based authentication
- Custom base URL support
- Similar sync flow to other providers

#### EnableBanking (EU Open Banking)

- PSD2 compliance
- ASPSP (bank) integration
- Session management with certificates

### Sync Architecture

**Syncable Concern**
- Polymorphic sync support for any model
- Provider-agnostic sync mechanism

**Sync State Machine**
```
pending → syncing → completed/failed/stale
```

**Key Features:**
- Parent/child syncs (hierarchical)
- Window-based sync (date range optimization)
- Post-sync hooks (balance recalculation, broadcasts)
- Sync stats tracking (imported/updated/deleted counts)

### Import System

**CSV Import Flow:**
1. Upload CSV file
2. Map columns to Sure fields
3. Preview with dry run
4. Publish to create records
5. Revert if needed

**Capabilities:**
- Number format detection (US, EU, French, Japanese)
- Date format customization
- Signage convention handling (inflows positive/negative)
- Template system for recurring imports
- Import types: Transaction, Trade, Account, Category, Rule, Mint

### Balance Calculation

**Forward Calculator**
- Starts from first valuation
- Applies entries forward in time
- Used for historical accuracy

**Reverse Calculator**
- Starts from latest balance
- Applies entries backward
- Used for validation

**Component Tracking:**
- Cash vs. non-cash
- Inflows vs. outflows
- Market value tracking for investments
- Currency normalization via exchange rates

---

## Testing Approach

### Test Framework

**Stack:**
- Minitest (NOT RSpec)
- Fixtures (NOT FactoryBot)
- VCR for external API mocking
- Mocha for stubs/mocks
- Capybara + Selenium for system tests

### Philosophy

**Write Minimal, Effective Tests**
- Only test critical code paths
- System tests used sparingly (slow)
- Focus on increasing confidence, not coverage

**Fixture Strategy**
- Keep minimal (2-3 per model for base cases)
- Create edge cases on-the-fly in tests
- Use Rails helpers for large fixture needs

**Boundary Testing**
- Commands: Test they were called with correct params
- Queries: Test output
- Don't test implementation details of other classes

### Test Structure

```
test/
├── fixtures/          # Test data (52 files)
├── models/            # Model tests (71 files)
├── controllers/       # Controller tests (53 files)
├── system/            # Browser tests (12 files, use sparingly)
├── jobs/              # Job tests (8 files)
├── integration/       # Integration tests
└── support/           # Test helpers
```

### Example: Good vs. Bad Tests

**Good - Testing Critical Domain Logic:**
```ruby
test "syncs balances" do
  Holding::Syncer.any_instance.expects(:sync_holdings).returns([]).once
  assert_difference "@account.balances.count", 2 do
    Balance::Syncer.new(@account, strategy: :forward).sync_balances
  end
end
```

**Bad - Testing Framework Functionality:**
```ruby
test "saves balance" do
  balance_record = Balance.new(balance: 100, currency: "USD")
  assert balance_record.save
end
```

---

## Directory Structure

### Application (`app/`)

```
app/
├── assets/
│   └── tailwind/              # Tailwind CSS v4, design system
├── channels/                  # ActionCable WebSocket channels
├── components/                # ViewComponents
│   ├── DS/                    # Design system components
│   └── UI/                    # Application-specific components
├── controllers/               # Rails controllers (64 files)
│   ├── api/v1/                # External API endpoints
│   ├── concerns/              # Controller mixins
│   ├── import/                # Import workflow controllers
│   ├── settings/              # Settings pages
│   └── transactions/          # Transaction management
├── data_migrations/           # One-time data transformations
├── helpers/                   # View helpers (15 files)
├── javascript/                # Stimulus controllers, services
│   ├── controllers/           # 51 Stimulus controllers
│   ├── services/              # JS utilities
│   └── shims/                 # Polyfills
├── jobs/                      # Sidekiq background jobs (23 files)
├── mailers/                   # ActionMailer classes
├── models/                    # Domain models (122+ files)
│   ├── account/               # Account-related classes
│   ├── assistant/             # AI assistant logic
│   ├── balance/               # Balance calculation
│   ├── balance_sheet/         # Financial reporting
│   ├── concerns/              # Model mixins
│   ├── family/                # Family-scoped logic
│   ├── holding/               # Investment holdings
│   ├── import/                # Import processing
│   ├── income_statement/      # P&L reporting
│   ├── plaid_*/               # Plaid integration
│   ├── simplefin_*/           # SimpleFin integration
│   ├── lunchflow_*/           # Lunchflow integration
│   ├── enable_banking_*/      # EnableBanking integration
│   ├── provider/              # Provider abstractions
│   ├── recurring_transaction/ # Pattern detection
│   ├── rule/                  # Rules engine
│   ├── security/              # Securities/stocks
│   ├── trade/                 # Investment trades
│   ├── transaction/           # Transaction logic
│   └── transfer/              # Transfer matching
├── services/                  # Service objects (minimal usage)
└── views/                     # ERB templates
```

### Configuration (`config/`)

```
config/
├── initializers/              # App configuration (28 files)
│   ├── doorkeeper.rb          # OAuth provider setup
│   ├── omniauth.rb            # OIDC setup
│   ├── plaid_config.rb        # Plaid API config
│   ├── simplefin.rb           # SimpleFin feature flags
│   ├── rack_attack.rb         # Rate limiting
│   ├── sidekiq.rb             # Background job config
│   └── sentry.rb              # Error tracking
├── locales/                   # i18n translations
├── routes.rb                  # Application routes
├── application.rb             # Rails app config
├── database.yml               # DB configuration
└── sidekiq.yml                # Job queue configuration
```

### Library (`lib/`)

```
lib/
├── money/                     # Money/currency handling
├── simplefin/                 # SimpleFin SDK
├── tasks/                     # Rake tasks
└── generators/                # Rails generators
```

### Tests (`test/`)

```
test/
├── fixtures/                  # Test data (52 files)
├── models/                    # Model tests (71 files)
├── controllers/               # Controller tests (53 files)
├── system/                    # Browser tests (12 files)
├── jobs/                      # Job tests (8 files)
├── integration/               # Integration tests
├── support/                   # Test helpers
└── vcr_cassettes/             # Recorded API responses
```

---

## Design Patterns & Conventions

### Polymorphism

**Delegated Types (STI Alternative)**
- `Account` uses `accountable` for account type polymorphism
- `Entry` uses `entryable` for transaction/trade/valuation
- Cleaner than Single Table Inheritance
- Better for distinct attributes per type

### State Machines

**AASM Gem**
- Account: active, draft, disabled, pending_deletion
- Sync: pending, syncing, completed, failed, stale
- Import: mapping, loading, publishing, uploaded, finished, deleted, error
- Clear transitions with callbacks

### Concerns for Shared Functionality

**Model Concerns:**
- `Syncable` - Polymorphic sync support
- `Ruleable` - Rules engine integration
- `Enrichable` - Data enrichment
- `Favorable` - User favorites

**Controller Concerns:**
- `Localized` - Family locale and timezone
- `SessionTracking` - Activity logging

### Money & Currency Handling

- Money gem for all monetary values
- Historical exchange rates for accuracy
- Multi-currency support throughout
- Server-side formatting (never client-side)

### Multi-Tenancy

**Family-Scoped Data**
- `Current.family` for current family
- All queries scoped to family
- Cache keys include family_id
- Prevent cross-family data access

### Performance Optimizations

**Caching**
- Aggressive caching with Rails.cache
- Cache key invalidation via timestamps
- Family-level cache keys
- Entry cache version for aggregations

**Query Optimization**
- N+1 prevention with includes/joins
- Virtual columns in PostgreSQL
- Indexes on foreign keys and queries
- Background jobs for heavy operations

### Security Measures

**Static Analysis**
- Brakeman for security scanning
- Run before every PR

**Data Protection**
- ActiveRecord encryption for sensitive fields
- CSRF protection
- Content Security Policy
- API rate limiting

**Error Tracking**
- Sentry for production errors
- Detailed error context
- User feedback integration

### Internationalization (i18n)

**Guidelines:**
- All user-facing strings must use i18n
- Hierarchical keys by feature (e.g., `accounts.index.title`)
- Interpolation for dynamic content
- Pluralization support
- Fallback to English

**Locale Files:**
- `config/locales/en.yml` - English translations
- Organized by feature/controller
- Update locale files for each new string

---

## Additional Key Insights

### Data Enrichment

- Pluggable enrichment system via Enrichable concern
- Merchant logo and website fetching
- Transaction categorization suggestions
- Stored in polymorphic `data_enrichments` table

### Provider Architecture

- Polymorphic `AccountProvider` model
- Provider-agnostic sync mechanism
- Raw payload storage for debugging
- Institution metadata caching
- Configurable via ENV variables

### Virtual Columns

- Account classification (asset/liability) computed in DB
- Performance benefits for reporting
- Maintains data integrity

### Lookbook Integration

- Component development environment
- Available at `/design-system` in development
- Live preview of all ViewComponents
- Interactive documentation

---

## Conclusion

Sure is a mature Rails application that demonstrates excellent architectural practices:

- **Domain-Driven Design:** Rich domain models with clear responsibilities
- **Rails Conventions:** Leverages Rails strengths, minimal custom abstractions
- **Modern Frontend:** Hotwire for reactive UI without heavy JavaScript
- **Scalability:** Multi-tenancy, caching, background jobs
- **Extensibility:** Provider integrations, rules engine, API
- **Maintainability:** Comprehensive tests, clear conventions, minimal dependencies

The codebase prioritizes simplicity, convention over configuration, and Rails best practices while handling the complexity of multi-currency financial data, provider integrations, and real-time syncing.
