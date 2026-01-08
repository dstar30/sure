# Scheduled Custom Report Generation - Implementation Plan

## Table of Contents

1. [Overview](#1-overview)
2. [Requirements](#2-requirements)
   - 2.1 [User Needs](#21-user-needs)
   - 2.2 [Functional Requirements](#22-functional-requirements)
   - 2.3 [Non-Functional Requirements](#23-non-functional-requirements)
3. [Technical Specification](#3-technical-specification)
   - 3.1 [Data Model](#31-data-model)
   - 3.2 [Report Types](#32-report-types)
   - 3.3 [Scheduling Engine](#33-scheduling-engine)
   - 3.4 [Delivery Mechanisms](#34-delivery-mechanisms)
   - 3.5 [API Design](#35-api-design)
   - 3.6 [UI Components](#36-ui-components)
4. [Implementation Plan](#4-implementation-plan)
   - 4.1 [Phase 1: Data Model & Schema](#41-phase-1-data-model--schema)
   - 4.2 [Phase 2: Report Generation Core](#42-phase-2-report-generation-core)
   - 4.3 [Phase 3: Background Job & Scheduling](#43-phase-3-background-job--scheduling)
   - 4.4 [Phase 4: Email Delivery](#44-phase-4-email-delivery)
   - 4.5 [Phase 5: CRUD Controllers & Routes](#45-phase-5-crud-controllers--routes)
   - 4.6 [Phase 6: User Interface](#46-phase-6-user-interface)
   - 4.7 [Phase 7: Testing & Documentation](#47-phase-7-testing--documentation)

---

## 1. Overview

**What We're Building:**
A scheduled report generation system that allows users to automatically generate and receive financial reports at recurring intervals (daily, weekly, monthly). Reports can be delivered via email or stored as downloadable files.

**Key Components:**
- `ScheduledReport` model for configuration storage
- `ReportGenerator` service for reusable report creation logic
- `GenerateScheduledReportJob` for background processing
- `ProcessScheduledReportsJob` for periodic execution (via sidekiq-cron)
- `ScheduledReportMailer` for email delivery
- CRUD interface for managing scheduled reports
- Dashboard for viewing report history and status

**Sequencing Logic:**
1. **Data model first** - Foundation for all other components
2. **Report generation** - Core business logic, reusable across manual and scheduled reports
3. **Scheduling infrastructure** - Job processing and cron integration
4. **Email delivery** - Presentation layer for report distribution
5. **CRUD & UI** - User-facing management interface
6. **Testing & docs** - Validation and documentation

---

## 2. Requirements

### 2.1 User Needs

**Primary User Stories:**
- As a user, I want to receive my monthly spending report via email automatically
- As a user, I want to schedule weekly income/expense summaries without manual export
- As a user, I want to configure which report types I receive and when
- As a user, I want to enable/disable scheduled reports without deleting the configuration
- As a user, I want to see the status of my scheduled reports (last run, next run, errors)

**Secondary User Stories:**
- As a user, I want to trigger a scheduled report manually on-demand
- As a user, I want to customize report date ranges (e.g., last 30 days vs calendar month)
- As a user, I want to send reports to multiple email addresses
- As a user, I want to choose report format (CSV vs PDF)

### 2.2 Functional Requirements

**FR-1: Report Configuration**
- Users can create scheduled reports with:
  - Report type (income/expense trends, spending patterns, transactions breakdown, budget performance)
  - Frequency (daily, weekly, monthly)
  - Delivery method (email, downloadable file, or both)
  - Email recipients (multiple addresses supported)
  - Date range preferences (last N days, calendar month, custom)
  - Format preference (CSV, PDF)

**FR-2: Scheduling Engine**
- System automatically processes scheduled reports at appropriate intervals
- Calculates next run time based on frequency
- Handles timezone considerations (user's timezone)
- Prevents duplicate runs
- Supports manual triggering

**FR-3: Report Generation**
- Reuses existing reports controller logic
- Generates reports asynchronously via background jobs
- Supports all existing report types from `/app/controllers/reports_controller.rb`
- Handles errors gracefully with status tracking

**FR-4: Email Delivery**
- Sends formatted emails with report attachments
- Supports HTML email templates
- Includes summary statistics in email body
- Uses family branding (product name, brand name)
- Localizable content (i18n)

**FR-5: Report Management UI**
- List view showing all scheduled reports with status
- Create/edit forms with validation
- Enable/disable toggle
- Delete with confirmation
- Manual trigger button
- Shows last run time, next run time, error messages

**FR-6: Audit & History**
- Tracks execution history (success/failure)
- Stores generated reports for download
- Shows error messages for failed runs
- Limits history retention (e.g., last 30 days)

### 2.3 Non-Functional Requirements

**Performance:**
- Report generation should complete within 30 seconds for typical datasets
- Email delivery should use high-priority queue
- Scheduled processing should not impact interactive requests

**Security:**
- Only family members can access scheduled reports
- Email recipients must be validated
- Report data scoped to current family
- API access requires authentication

**Reliability:**
- Failed report generation should retry (up to 3 attempts)
- Email delivery failures should be logged
- System should continue processing other reports if one fails

**Scalability:**
- Support up to 10 scheduled reports per family
- Handle concurrent report generation across families
- Efficient database queries (no N+1)

**Usability:**
- Clear error messages for invalid configurations
- Timezone-aware scheduling display
- Mobile-responsive UI
- Accessible forms (ARIA support)

---

## 3. Technical Specification

### 3.1 Data Model

#### ScheduledReport Model

**Table:** `scheduled_reports`

**Columns:**
```ruby
t.references :family, null: false, foreign_key: true, index: true
t.references :user, null: false, foreign_key: true  # Creator/owner
t.string :name, null: false  # User-friendly name
t.string :report_type, null: false  # income_expense, spending, transactions, budget
t.string :frequency, null: false  # daily, weekly, monthly
t.string :delivery_method, null: false  # email, file, both
t.jsonb :recipients, default: []  # Array of email addresses
t.jsonb :preferences, default: {}  # Report-specific options
t.boolean :enabled, default: true, null: false
t.datetime :last_run_at
t.datetime :next_run_at
t.datetime :last_success_at
t.text :last_error
t.timestamps
```

**Indexes:**
```ruby
add_index :scheduled_reports, [:family_id, :enabled]
add_index :scheduled_reports, :next_run_at, where: "enabled = true"
```

**Enums:**
```ruby
enum :report_type, {
  income_expense: "income_expense",
  spending: "spending",
  transactions: "transactions",
  budget: "budget"
}

enum :frequency, {
  daily: "daily",
  weekly: "weekly",
  monthly: "monthly"
}

enum :delivery_method, {
  email: "email",
  file: "file",
  both: "both"
}
```

**Validations:**
```ruby
validates :name, presence: true, length: { maximum: 100 }
validates :report_type, presence: true, inclusion: { in: report_types.keys }
validates :frequency, presence: true, inclusion: { in: frequencies.keys }
validates :delivery_method, presence: true, inclusion: { in: delivery_methods.keys }
validates :recipients, presence: true, if: -> { email? || both? }
validate :validate_recipients_format
validate :validate_preferences_schema
```

**Associations:**
```ruby
belongs_to :family
belongs_to :user
has_many :scheduled_report_runs, dependent: :destroy
```

**Scopes:**
```ruby
scope :enabled, -> { where(enabled: true) }
scope :due, -> { enabled.where("next_run_at <= ?", Time.current) }
scope :ordered, -> { order(next_run_at: :asc, created_at: :desc) }
```

**Key Methods:**
```ruby
# Calculate next run time based on frequency and last run
def calculate_next_run_at
  base_time = last_run_at || Time.current

  case frequency
  when "daily"
    base_time.tomorrow.beginning_of_day + 6.hours  # 6 AM
  when "weekly"
    base_time.next_week.beginning_of_week + 6.hours  # Monday 6 AM
  when "monthly"
    base_time.next_month.beginning_of_month + 6.hours  # 1st of month, 6 AM
  end
end

# Mark successful run and update next run time
def mark_success!
  update!(
    last_run_at: Time.current,
    last_success_at: Time.current,
    next_run_at: calculate_next_run_at,
    last_error: nil
  )
end

# Mark failed run with error message
def mark_failure!(error_message)
  update!(
    last_run_at: Time.current,
    next_run_at: calculate_next_run_at,
    last_error: error_message.truncate(500)
  )
end
```

#### ScheduledReportRun Model

**Table:** `scheduled_report_runs`

**Purpose:** Track execution history for audit and debugging

**Columns:**
```ruby
t.references :scheduled_report, null: false, foreign_key: true, index: true
t.string :status, null: false  # pending, processing, completed, failed
t.datetime :started_at
t.datetime :completed_at
t.text :error_message
t.jsonb :metadata, default: {}  # Record count, file size, etc.
t.timestamps
```

**Enums:**
```ruby
enum :status, {
  pending: "pending",
  processing: "processing",
  completed: "completed",
  failed: "failed"
}
```

**Active Storage Attachment:**
```ruby
has_one_attached :report_file
```

**Scopes:**
```ruby
scope :recent, -> { order(created_at: :desc).limit(30) }
scope :successful, -> { where(status: :completed) }
scope :failed, -> { where(status: :failed) }
```

### 3.2 Report Types

Leverage existing report logic from `ReportsController`:

**Income/Expense Trends (`income_expense`):**
- 6-month trend analysis
- Monthly income, expenses, net savings
- Percentage change indicators
- Chart data for visualization

**Spending Patterns (`spending`):**
- Weekday vs weekend analysis
- Category breakdown
- Time-based patterns

**Transactions Breakdown (`transactions`):**
- By category, type, account
- Monthly columns with totals
- CSV export format

**Budget Performance (`budget`):**
- Budget vs actual comparison
- Variance analysis
- Category-level details

### 3.3 Scheduling Engine

**Cron Job Configuration** (`config/schedule.yml`):
```yaml
process_scheduled_reports:
  cron: "0 */2 * * *"  # Every 2 hours
  class: "ProcessScheduledReportsJob"
  queue: "scheduled"
```

**Job Execution Flow:**
1. `ProcessScheduledReportsJob` queries for due reports
2. Enqueues `GenerateScheduledReportJob` for each
3. Individual jobs generate reports and handle delivery
4. Updates `next_run_at` and status tracking

**Timezone Handling:**
- Store `next_run_at` in UTC
- Calculate based on family timezone (if available) or server timezone
- Display in user's local timezone in UI

### 3.4 Delivery Mechanisms

**Email Delivery:**
- Uses `ScheduledReportMailer`
- Queue: `:high_priority`
- Attachments: CSV or PDF files
- HTML email with summary statistics
- Supports multiple recipients

**File Storage:**
- Active Storage for report files
- Attached to `ScheduledReportRun` model
- Retention: 30 days (configurable)
- Cleanup via background job

### 3.5 API Design

**Routes:**
```ruby
# config/routes.rb
resources :scheduled_reports do
  member do
    post :trigger  # Manual execution
    patch :toggle  # Enable/disable
  end

  resources :runs, only: [:index, :show], controller: "scheduled_report_runs"
end
```

**Controller Actions:**
- `index` - List all scheduled reports for current family
- `show` - View single scheduled report with recent runs
- `new` - Form for creating new scheduled report
- `create` - Save new scheduled report
- `edit` - Form for editing existing scheduled report
- `update` - Save changes to scheduled report
- `destroy` - Delete scheduled report
- `trigger` - Manually execute scheduled report
- `toggle` - Enable/disable scheduled report

**JSON API Support:**
- Optional API endpoints for third-party integrations
- Requires API key authentication with `read_write` scope
- Follows existing API patterns in `/api/v1/`

### 3.6 UI Components

**Scheduled Reports Dashboard:**
- Table view with columns: Name, Type, Frequency, Last Run, Next Run, Status, Actions
- Status badges (success, failed, pending)
- Enable/disable toggle switches
- Edit, Delete, Trigger buttons
- "New Scheduled Report" CTA

**Create/Edit Form:**
- Name input (text field)
- Report type select (dropdown)
- Frequency select (daily/weekly/monthly)
- Delivery method checkboxes (email, file)
- Recipients input (multi-email field, shown if email delivery selected)
- Date range preferences (last N days, calendar period)
- Format select (CSV, PDF)
- Enable checkbox
- Save/Cancel buttons

**Report Run History:**
- List of recent runs (last 30)
- Status, date, download link (if file generated)
- Error messages for failed runs
- Filterable by status

**Navigation Integration:**
- Add "Scheduled Reports" link in settings or reports section
- Badge showing count of failed reports

---

## 4. Implementation Plan

### 4.1 Phase 1: Data Model & Schema

**Justification:** Implements spec sections 3.1 (Data Model). Foundation for all subsequent phases.

**Tasks:**

- [ ] Create migration for `scheduled_reports` table with all columns and indexes
  ```ruby
  # db/migrate/YYYYMMDDHHMMSS_create_scheduled_reports.rb
  class CreateScheduledReports < ActiveRecord::Migration[8.0]
    def change
      create_table :scheduled_reports do |t|
        t.references :family, null: false, foreign_key: true, index: true
        t.references :user, null: false, foreign_key: true
        t.string :name, null: false
        t.string :report_type, null: false
        t.string :frequency, null: false
        t.string :delivery_method, null: false
        t.jsonb :recipients, default: []
        t.jsonb :preferences, default: {}
        t.boolean :enabled, default: true, null: false
        t.datetime :last_run_at
        t.datetime :next_run_at
        t.datetime :last_success_at
        t.text :last_error
        t.timestamps
      end

      add_index :scheduled_reports, [:family_id, :enabled]
      add_index :scheduled_reports, :next_run_at, where: "enabled = true"
    end
  end
  ```

- [ ] Create migration for `scheduled_report_runs` table
  ```ruby
  # db/migrate/YYYYMMDDHHMMSS_create_scheduled_report_runs.rb
  class CreateScheduledReportRuns < ActiveRecord::Migration[8.0]
    def change
      create_table :scheduled_report_runs do |t|
        t.references :scheduled_report, null: false, foreign_key: true, index: true
        t.string :status, null: false, default: "pending"
        t.datetime :started_at
        t.datetime :completed_at
        t.text :error_message
        t.jsonb :metadata, default: {}
        t.timestamps
      end

      add_index :scheduled_report_runs, [:scheduled_report_id, :created_at]
    end
  end
  ```

- [ ] Create `ScheduledReport` model in `app/models/scheduled_report.rb`
  ```ruby
  # == Schema Information
  #
  # Table name: scheduled_reports
  #
  #  id              :bigint           not null, primary key
  #  delivery_method :string           not null
  #  enabled         :boolean          default(TRUE), not null
  #  frequency       :string           not null
  #  last_error      :text
  #  last_run_at     :datetime
  #  last_success_at :datetime
  #  name            :string           not null
  #  next_run_at     :datetime
  #  preferences     :jsonb
  #  recipients      :jsonb
  #  report_type     :string           not null
  #  created_at      :datetime         not null
  #  updated_at      :datetime         not null
  #  family_id       :bigint           not null
  #  user_id         :bigint           not null
  #
  # Indexes
  #
  #  index_scheduled_reports_on_family_id              (family_id)
  #  index_scheduled_reports_on_family_id_and_enabled  (family_id,enabled)
  #  index_scheduled_reports_on_next_run_at            (next_run_at) WHERE (enabled = true)
  #  index_scheduled_reports_on_user_id                (user_id)
  #
  class ScheduledReport < ApplicationRecord
    belongs_to :family
    belongs_to :user
    has_many :scheduled_report_runs, dependent: :destroy

    # Enums
    enum :report_type, {
      income_expense: "income_expense",
      spending: "spending",
      transactions: "transactions",
      budget: "budget"
    }, validate: true

    enum :frequency, {
      daily: "daily",
      weekly: "weekly",
      monthly: "monthly"
    }, validate: true

    enum :delivery_method, {
      email: "email",
      file: "file",
      both: "both"
    }, validate: true

    # Validations
    validates :name, presence: true, length: { maximum: 100 }
    validates :report_type, presence: true
    validates :frequency, presence: true
    validates :delivery_method, presence: true
    validates :recipients, presence: true, if: -> { email? || both? }
    validate :validate_recipients_format, if: -> { recipients.present? }
    validate :validate_preferences_schema

    # Scopes
    scope :enabled, -> { where(enabled: true) }
    scope :due, -> { enabled.where("next_run_at <= ?", Time.current) }
    scope :ordered, -> { order(next_run_at: :asc, created_at: :desc) }

    # Callbacks
    before_create :set_initial_next_run_at

    # Calculate next run time based on frequency
    #
    # @return [ActiveSupport::TimeWithZone] Next scheduled run time in UTC
    def calculate_next_run_at
      base_time = last_run_at || Time.current

      case frequency
      when "daily"
        base_time.tomorrow.beginning_of_day + 6.hours
      when "weekly"
        base_time.next_week.beginning_of_week + 6.hours
      when "monthly"
        base_time.next_month.beginning_of_month + 6.hours
      end
    end

    # Mark successful run and update next run time
    #
    # @return [Boolean] Whether the update succeeded
    def mark_success!
      update!(
        last_run_at: Time.current,
        last_success_at: Time.current,
        next_run_at: calculate_next_run_at,
        last_error: nil
      )
    end

    # Mark failed run with error message
    #
    # @param error_message [String] Error description
    # @return [Boolean] Whether the update succeeded
    def mark_failure!(error_message)
      update!(
        last_run_at: Time.current,
        next_run_at: calculate_next_run_at,
        last_error: error_message.to_s.truncate(500)
      )
    end

    # Check if report is currently due for execution
    #
    # @return [Boolean] True if enabled and next_run_at is in the past
    def due?
      enabled? && next_run_at.present? && next_run_at <= Time.current
    end

    private

    def set_initial_next_run_at
      self.next_run_at ||= calculate_next_run_at
    end

    def validate_recipients_format
      return if recipients.blank?

      unless recipients.is_a?(Array)
        errors.add(:recipients, "must be an array")
        return
      end

      recipients.each do |email|
        unless email.match?(URI::MailTo::EMAIL_REGEXP)
          errors.add(:recipients, "contains invalid email: #{email}")
        end
      end
    end

    def validate_preferences_schema
      return if preferences.blank?

      unless preferences.is_a?(Hash)
        errors.add(:preferences, "must be a hash")
      end
    end
  end
  ```

- [ ] Create `ScheduledReportRun` model in `app/models/scheduled_report_run.rb`
  ```ruby
  # == Schema Information
  #
  # Table name: scheduled_report_runs
  #
  #  id                  :bigint           not null, primary key
  #  completed_at        :datetime
  #  error_message       :text
  #  metadata            :jsonb
  #  started_at          :datetime
  #  status              :string           default("pending"), not null
  #  created_at          :datetime         not null
  #  updated_at          :datetime         not null
  #  scheduled_report_id :bigint           not null
  #
  # Indexes
  #
  #  index_scheduled_report_runs_on_scheduled_report_id               (scheduled_report_id)
  #  index_scheduled_report_runs_on_scheduled_report_id_and_created_at (scheduled_report_id,created_at)
  #
  class ScheduledReportRun < ApplicationRecord
    belongs_to :scheduled_report
    has_one_attached :report_file

    # Enums
    enum :status, {
      pending: "pending",
      processing: "processing",
      completed: "completed",
      failed: "failed"
    }, validate: true

    # Scopes
    scope :recent, -> { order(created_at: :desc).limit(30) }
    scope :successful, -> { where(status: :completed) }
    scope :failed, -> { where(status: :failed) }

    # Check if report file is available for download
    #
    # @return [Boolean] True if status is completed and file is attached
    def downloadable?
      completed? && report_file.attached?
    end

    # Get formatted filename for download
    #
    # @return [String] Filename with timestamp
    def filename
      return nil unless report_file.attached?

      timestamp = created_at.strftime("%Y%m%d_%H%M%S")
      "#{scheduled_report.report_type}_report_#{timestamp}.csv"
    end

    # Calculate duration of report generation
    #
    # @return [Float, nil] Duration in seconds, or nil if not completed
    def duration
      return nil unless started_at && completed_at

      completed_at - started_at
    end
  end
  ```

- [ ] Add associations to `Family` model
  ```ruby
  # In app/models/family.rb, add:
  has_many :scheduled_reports, dependent: :destroy
  ```

- [ ] Add associations to `User` model
  ```ruby
  # In app/models/user.rb, add:
  has_many :scheduled_reports, dependent: :destroy
  ```

- [ ] Run migrations: `bin/rails db:migrate`

- [ ] Create fixture data for testing in `test/fixtures/scheduled_reports.yml`
  ```yaml
  monthly_income_expense:
    family: dylan_family
    user: dylan
    name: "Monthly Income & Expense Report"
    report_type: income_expense
    frequency: monthly
    delivery_method: email
    recipients: ["dylan@example.com"]
    enabled: true
    next_run_at: <%= 1.day.from_now %>

  weekly_spending:
    family: dylan_family
    user: dylan
    name: "Weekly Spending Report"
    report_type: spending
    frequency: weekly
    delivery_method: both
    recipients: ["dylan@example.com", "family@example.com"]
    enabled: false
    last_run_at: <%= 3.days.ago %>
    last_success_at: <%= 3.days.ago %>
    next_run_at: <%= 4.days.from_now %>
  ```

- [ ] Create fixture data for `test/fixtures/scheduled_report_runs.yml`
  ```yaml
  recent_success:
    scheduled_report: monthly_income_expense
    status: completed
    started_at: <%= 1.day.ago %>
    completed_at: <%= 1.day.ago + 5.seconds %>
    metadata: { record_count: 150 }

  recent_failure:
    scheduled_report: weekly_spending
    status: failed
    started_at: <%= 2.days.ago %>
    completed_at: <%= 2.days.ago + 2.seconds %>
    error_message: "Insufficient data for report generation"
  ```

- [ ] Write model tests in `test/models/scheduled_report_test.rb`
  - Test validations (presence, format, enum values)
  - Test `calculate_next_run_at` for all frequencies
  - Test `mark_success!` updates timestamps correctly
  - Test `mark_failure!` stores error message
  - Test `due?` scoping logic
  - Test recipient email validation
  - Follow existing model test patterns from `test/models/family_export_test.rb`

- [ ] Write model tests in `test/models/scheduled_report_run_test.rb`
  - Test status transitions
  - Test `downloadable?` logic
  - Test `filename` generation
  - Test `duration` calculation
  - Follow existing test patterns

### 4.2 Phase 2: Report Generation Core

**Justification:** Implements spec sections 3.2 (Report Types). Core business logic needed before scheduling and delivery.

**Tasks:**

- [ ] Create `ReportGenerator` service in `app/models/report_generator.rb`
  ```ruby
  # Service object for generating reports across different types and formats
  #
  # This service encapsulates report generation logic, making it reusable
  # for both manual exports (via ReportsController) and scheduled reports.
  #
  # @example Generate a CSV report
  #   generator = ReportGenerator.new(
  #     family: current_family,
  #     report_type: "income_expense",
  #     format: "csv",
  #     preferences: { period: "last_30_days" }
  #   )
  #   csv_data = generator.generate
  #
  class ReportGenerator
    attr_reader :family, :report_type, :format, :preferences

    # Initialize a new report generator
    #
    # @param family [Family] The family to generate report for
    # @param report_type [String] Type of report (income_expense, spending, transactions, budget)
    # @param format [String] Output format (csv, pdf)
    # @param preferences [Hash] Report-specific options (period, filters, etc.)
    def initialize(family:, report_type:, format: "csv", preferences: {})
      @family = family
      @report_type = report_type
      @format = format
      @preferences = preferences
    end

    # Generate the report and return as string
    #
    # @return [String] Report content (CSV or PDF data)
    # @raise [ArgumentError] If report_type or format is invalid
    def generate
      validate_inputs!

      case report_type
      when "income_expense"
        generate_income_expense_report
      when "spending"
        generate_spending_report
      when "transactions"
        generate_transactions_report
      when "budget"
        generate_budget_report
      else
        raise ArgumentError, "Unknown report type: #{report_type}"
      end
    end

    # Get report metadata (record counts, date ranges, etc.)
    #
    # @return [Hash] Metadata about the generated report
    def metadata
      {
        report_type: report_type,
        format: format,
        generated_at: Time.current,
        period: period,
        record_count: calculate_record_count
      }
    end

    private

    def validate_inputs!
      unless %w[income_expense spending transactions budget].include?(report_type)
        raise ArgumentError, "Invalid report_type: #{report_type}"
      end

      unless %w[csv pdf].include?(format)
        raise ArgumentError, "Invalid format: #{format}"
      end
    end

    # Get period from preferences or default to last 30 days
    def period
      @period ||= begin
        period_key = preferences[:period] || "last_30_days"
        Period.from_param(period_key)
      rescue
        Period.last_30_days
      end
    end

    # Generate income/expense trends report
    # Reuses logic from ReportsController#income_expense_trends
    def generate_income_expense_report
      # This follows the pattern from app/controllers/reports_controller.rb
      # Calculate 6-month trends with income, expenses, net savings

      data = calculate_income_expense_trends

      case format
      when "csv"
        generate_csv(data, columns: income_expense_columns)
      when "pdf"
        generate_pdf(data, template: :income_expense)
      end
    end

    def generate_spending_report
      data = calculate_spending_patterns

      case format
      when "csv"
        generate_csv(data, columns: spending_columns)
      when "pdf"
        generate_pdf(data, template: :spending)
      end
    end

    def generate_transactions_report
      data = calculate_transactions_breakdown

      case format
      when "csv"
        generate_csv(data, columns: transactions_columns)
      when "pdf"
        generate_pdf(data, template: :transactions)
      end
    end

    def generate_budget_report
      data = calculate_budget_performance

      case format
      when "csv"
        generate_csv(data, columns: budget_columns)
      when "pdf"
        generate_pdf(data, template: :budget)
      end
    end

    # Generate CSV from data hash
    def generate_csv(data, columns:)
      CSV.generate do |csv|
        csv << columns.map(&:first)  # Headers

        data.each do |row|
          csv << columns.map { |col| format_cell(row[col.last]) }
        end
      end
    end

    def format_cell(value)
      case value
      when Money
        value.format
      when Date, Time, DateTime
        value.strftime("%Y-%m-%d")
      else
        value.to_s
      end
    end

    # Calculation methods - reference existing ReportsController logic
    # These would reuse the actual calculation logic from the controller

    def calculate_income_expense_trends
      # Reference: ReportsController#income_expense_trends
      # Returns array of hashes with monthly data
    end

    def calculate_spending_patterns
      # Reference: ReportsController#spending_patterns
    end

    def calculate_transactions_breakdown
      # Reference: ReportsController#transactions_breakdown
    end

    def calculate_budget_performance
      # Reference: ReportsController#budget_performance
    end

    def calculate_record_count
      # Return number of records in the report
      # Implementation depends on report type
    end

    # Column definitions for CSV export
    def income_expense_columns
      [
        ["Month", :month],
        ["Income", :income],
        ["Expenses", :expenses],
        ["Net Savings", :net_savings],
        ["Change %", :change_percent]
      ]
    end

    def spending_columns
      [
        ["Category", :category],
        ["Weekday", :weekday],
        ["Weekend", :weekend],
        ["Total", :total]
      ]
    end

    def transactions_columns
      [
        ["Date", :date],
        ["Account", :account],
        ["Category", :category],
        ["Description", :description],
        ["Amount", :amount]
      ]
    end

    def budget_columns
      [
        ["Category", :category],
        ["Budgeted", :budgeted],
        ["Actual", :actual],
        ["Variance", :variance],
        ["% Used", :percent_used]
      ]
    end
  end
  ```

- [ ] Extract calculation logic from `ReportsController` into private methods
  - Keep existing controller endpoints functional
  - Make calculation methods reusable by `ReportGenerator`
  - Consider creating a `Reports::Calculator` concern if logic is complex
  - Reference pattern: `app/models/balance/chart_series_builder.rb` for complex calculations

- [ ] Write comprehensive tests for `ReportGenerator` in `test/models/report_generator_test.rb`
  - Test each report type generates valid CSV
  - Test period preferences are respected
  - Test error handling for invalid inputs
  - Test metadata generation
  - Use fixtures for predictable test data
  - Mock calculation methods if needed (focus on generator logic, not calculation accuracy)

- [ ] Add helper method to generate filename
  ```ruby
  # In ReportGenerator class
  def filename
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    "#{report_type}_report_#{timestamp}.#{format}"
  end
  ```

### 4.3 Phase 3: Background Job & Scheduling

**Justification:** Implements spec section 3.3 (Scheduling Engine). Enables automated report generation.

**Tasks:**

- [ ] Create `GenerateScheduledReportJob` in `app/jobs/generate_scheduled_report_job.rb`
  ```ruby
  # Background job for generating a single scheduled report
  #
  # This job is enqueued by ProcessScheduledReportsJob for each due report.
  # It generates the report, handles delivery, and updates status tracking.
  #
  # @example Enqueue a report generation
  #   GenerateScheduledReportJob.perform_later(scheduled_report)
  #
  class GenerateScheduledReportJob < ApplicationJob
    queue_as :default

    retry_on StandardError, wait: :exponentially_longer, attempts: 3
    discard_on ActiveRecord::RecordNotFound

    # Generate and deliver a scheduled report
    #
    # @param scheduled_report [ScheduledReport] The scheduled report to generate
    def perform(scheduled_report)
      # Create run record to track execution
      run = scheduled_report.scheduled_report_runs.create!(
        status: :processing,
        started_at: Time.current
      )

      begin
        # Generate report using ReportGenerator
        generator = ReportGenerator.new(
          family: scheduled_report.family,
          report_type: scheduled_report.report_type,
          format: extract_format_preference(scheduled_report),
          preferences: scheduled_report.preferences
        )

        report_content = generator.generate
        metadata = generator.metadata

        # Handle file storage if needed
        if scheduled_report.file? || scheduled_report.both?
          attach_report_file(run, generator.filename, report_content)
        end

        # Handle email delivery if needed
        if scheduled_report.email? || scheduled_report.both?
          deliver_report_email(scheduled_report, run, report_content)
        end

        # Mark run as successful
        run.update!(
          status: :completed,
          completed_at: Time.current,
          metadata: metadata
        )

        # Update scheduled report status
        scheduled_report.mark_success!

      rescue => e
        # Log error and mark as failed
        Rails.logger.error("Scheduled report generation failed: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))

        run.update!(
          status: :failed,
          completed_at: Time.current,
          error_message: e.message
        )

        scheduled_report.mark_failure!(e.message)

        # Re-raise to trigger retry logic
        raise
      end
    end

    private

    def extract_format_preference(scheduled_report)
      scheduled_report.preferences[:format] || "csv"
    end

    def attach_report_file(run, filename, content)
      run.report_file.attach(
        io: StringIO.new(content),
        filename: filename,
        content_type: content_type_for_format(filename)
      )
    end

    def content_type_for_format(filename)
      case File.extname(filename)
      when ".csv"
        "text/csv"
      when ".pdf"
        "application/pdf"
      else
        "application/octet-stream"
      end
    end

    def deliver_report_email(scheduled_report, run, report_content)
      ScheduledReportMailer.with(
        scheduled_report: scheduled_report,
        run: run,
        report_content: report_content
      ).report_email.deliver_later(queue: :high_priority)
    end
  end
  ```

- [ ] Create `ProcessScheduledReportsJob` in `app/jobs/process_scheduled_reports_job.rb`
  ```ruby
  # Periodic job to process all due scheduled reports
  #
  # This job runs every 2 hours via sidekiq-cron and enqueues
  # GenerateScheduledReportJob for each due report.
  #
  class ProcessScheduledReportsJob < ApplicationJob
    queue_as :scheduled

    # Sidekiq-unique-jobs lock to prevent concurrent execution
    sidekiq_options lock: :until_executed, on_conflict: :log

    def perform
      due_reports = ScheduledReport.due

      Rails.logger.info("Processing #{due_reports.count} due scheduled reports")

      due_reports.find_each do |scheduled_report|
        begin
          GenerateScheduledReportJob.perform_later(scheduled_report)
        rescue => e
          Rails.logger.error(
            "Failed to enqueue scheduled report #{scheduled_report.id}: #{e.message}"
          )

          # Mark as failed but continue processing other reports
          scheduled_report.mark_failure!("Failed to enqueue: #{e.message}")
        end
      end
    end
  end
  ```

- [ ] Add job to sidekiq-cron schedule in `config/schedule.yml`
  ```yaml
  process_scheduled_reports:
    cron: "0 */2 * * *"  # Every 2 hours
    class: "ProcessScheduledReportsJob"
    queue: "scheduled"
  ```

- [ ] Write job tests in `test/jobs/generate_scheduled_report_job_test.rb`
  ```ruby
  require "test_helper"

  class GenerateScheduledReportJobTest < ActiveJob::TestCase
    setup do
      @scheduled_report = scheduled_reports(:monthly_income_expense)
    end

    test "generates report and creates run record" do
      assert_difference "ScheduledReportRun.count", 1 do
        GenerateScheduledReportJob.perform_now(@scheduled_report)
      end

      run = @scheduled_report.scheduled_report_runs.last
      assert run.completed?
      assert run.report_file.attached?
    end

    test "sends email when delivery method is email" do
      @scheduled_report.update!(delivery_method: :email)

      assert_emails 1 do
        GenerateScheduledReportJob.perform_now(@scheduled_report)
      end
    end

    test "handles errors and marks run as failed" do
      ReportGenerator.any_instance.expects(:generate).raises(StandardError.new("Test error"))

      assert_raises(StandardError) do
        GenerateScheduledReportJob.perform_now(@scheduled_report)
      end

      run = @scheduled_report.scheduled_report_runs.last
      assert run.failed?
      assert_includes run.error_message, "Test error"
    end

    test "updates scheduled report next_run_at on success" do
      original_next_run = @scheduled_report.next_run_at

      GenerateScheduledReportJob.perform_now(@scheduled_report)

      @scheduled_report.reload
      assert @scheduled_report.next_run_at > original_next_run
      assert @scheduled_report.last_success_at.present?
    end
  end
  ```

- [ ] Write job tests in `test/jobs/process_scheduled_reports_job_test.rb`
  ```ruby
  require "test_helper"

  class ProcessScheduledReportsJobTest < ActiveJob::TestCase
    test "enqueues job for each due report" do
      # Create 3 due reports
      3.times do |i|
        ScheduledReport.create!(
          family: families(:dylan_family),
          user: users(:dylan),
          name: "Test Report #{i}",
          report_type: :income_expense,
          frequency: :daily,
          delivery_method: :email,
          recipients: ["test@example.com"],
          next_run_at: 1.hour.ago
        )
      end

      assert_enqueued_jobs 3, only: GenerateScheduledReportJob do
        ProcessScheduledReportsJob.perform_now
      end
    end

    test "does not enqueue jobs for disabled reports" do
      ScheduledReport.create!(
        family: families(:dylan_family),
        user: users(:dylan),
        name: "Disabled Report",
        report_type: :income_expense,
        frequency: :daily,
        delivery_method: :email,
        recipients: ["test@example.com"],
        enabled: false,
        next_run_at: 1.hour.ago
      )

      assert_no_enqueued_jobs only: GenerateScheduledReportJob do
        ProcessScheduledReportsJob.perform_now
      end
    end
  end
  ```

### 4.4 Phase 4: Email Delivery

**Justification:** Implements spec section 3.4 (Delivery Mechanisms). User-facing notification system.

**Tasks:**

- [ ] Create `ScheduledReportMailer` in `app/mailers/scheduled_report_mailer.rb`
  ```ruby
  # Mailer for delivering scheduled reports via email
  #
  # Sends formatted emails with report attachments and summary statistics.
  # Supports multiple recipients and localized content.
  #
  # @example Send a report email
  #   ScheduledReportMailer.with(
  #     scheduled_report: report,
  #     run: run,
  #     report_content: csv_data
  #   ).report_email.deliver_later
  #
  class ScheduledReportMailer < ApplicationMailer
    # Send scheduled report via email
    #
    # @param scheduled_report [ScheduledReport] The scheduled report configuration
    # @param run [ScheduledReportRun] The report run record
    # @param report_content [String] Generated report content (CSV/PDF)
    def report_email
      @scheduled_report = params[:scheduled_report]
      @run = params[:run]
      @family = @scheduled_report.family

      # Attach report file
      filename = "#{@scheduled_report.report_type}_report_#{@run.created_at.strftime('%Y%m%d')}.csv"
      attachments[filename] = params[:report_content]

      # Send to all configured recipients
      mail(
        to: @scheduled_report.recipients,
        subject: t(
          ".subject",
          report_name: @scheduled_report.name,
          product_name: product_name
        )
      )
    end
  end
  ```

- [ ] Create email template in `app/views/scheduled_report_mailer/report_email.html.erb`
  ```erb
  <!DOCTYPE html>
  <html>
    <head>
      <meta content='text/html; charset=UTF-8' http-equiv='Content-Type' />
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background-color: #f8f9fa; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .summary { background-color: #fff; border: 1px solid #dee2e6; padding: 15px; border-radius: 8px; margin-bottom: 20px; }
        .footer { color: #6c757d; font-size: 14px; margin-top: 30px; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1><%= t(".heading", report_name: @scheduled_report.name) %></h1>
          <p><%= t(".generated_at", time: l(@run.created_at, format: :long)) %></p>
        </div>

        <div class="summary">
          <h2><%= t(".summary_heading") %></h2>
          <p><%= t(".report_type", type: @scheduled_report.report_type.humanize) %></p>
          <p><%= t(".frequency", frequency: @scheduled_report.frequency.humanize) %></p>

          <% if @run.metadata["record_count"].present? %>
            <p><%= t(".record_count", count: @run.metadata["record_count"]) %></p>
          <% end %>
        </div>

        <p><%= t(".body") %></p>

        <p><%= link_to t(".view_online"), scheduled_report_run_url(@scheduled_report, @run) %></p>

        <div class="footer">
          <p><%= t(".automated_message") %></p>
        </div>
      </div>
    </body>
  </html>
  ```

- [ ] Create plain text template in `app/views/scheduled_report_mailer/report_email.text.erb`
  ```erb
  <%= t(".heading", report_name: @scheduled_report.name) %>

  <%= t(".generated_at", time: l(@run.created_at, format: :long)) %>

  <%= t(".summary_heading") %>
  - <%= t(".report_type", type: @scheduled_report.report_type.humanize) %>
  - <%= t(".frequency", frequency: @scheduled_report.frequency.humanize) %>
  <% if @run.metadata["record_count"].present? %>
  - <%= t(".record_count", count: @run.metadata["record_count"]) %>
  <% end %>

  <%= t(".body") %>

  <%= t(".view_online") %>: <%= scheduled_report_run_url(@scheduled_report, @run) %>

  <%= t(".automated_message") %>
  ```

- [ ] Add localization in `config/locales/mailers/scheduled_report_mailer.en.yml`
  ```yaml
  en:
    scheduled_report_mailer:
      report_email:
        subject: "Your %{report_name} from %{product_name}"
        heading: "%{report_name}"
        generated_at: "Generated at %{time}"
        summary_heading: "Report Summary"
        report_type: "Type: %{type}"
        frequency: "Frequency: %{frequency}"
        record_count: "Records included: %{count}"
        body: "Your scheduled report is attached. You can also view it online using the link below."
        view_online: "View Report Online"
        automated_message: "This is an automated message from your scheduled reports. To manage your scheduled reports, visit your account settings."
  ```

- [ ] Write mailer tests in `test/mailers/scheduled_report_mailer_test.rb`
  ```ruby
  require "test_helper"

  class ScheduledReportMailerTest < ActionMailer::TestCase
    setup do
      @scheduled_report = scheduled_reports(:monthly_income_expense)
      @run = scheduled_report_runs(:recent_success)
      @report_content = "Date,Amount\n2024-01-01,100.00"
    end

    test "sends report email with attachment" do
      email = ScheduledReportMailer.with(
        scheduled_report: @scheduled_report,
        run: @run,
        report_content: @report_content
      ).report_email

      assert_emails 1 do
        email.deliver_now
      end

      assert_equal @scheduled_report.recipients, email.to
      assert_includes email.subject, @scheduled_report.name
      assert_equal 1, email.attachments.size
      assert_equal @report_content, email.attachments.first.body.decoded
    end

    test "email includes summary information" do
      email = ScheduledReportMailer.with(
        scheduled_report: @scheduled_report,
        run: @run,
        report_content: @report_content
      ).report_email

      assert_includes email.body.encoded, @scheduled_report.name
      assert_includes email.body.encoded, @scheduled_report.report_type.humanize
    end
  end
  ```

- [ ] Add mailer preview in `test/mailers/previews/scheduled_report_mailer_preview.rb`
  ```ruby
  class ScheduledReportMailerPreview < ActionMailer::Preview
    def report_email
      scheduled_report = ScheduledReport.first || ScheduledReport.new(
        name: "Monthly Income & Expense Report",
        report_type: :income_expense,
        frequency: :monthly,
        recipients: ["user@example.com"]
      )

      run = ScheduledReportRun.new(
        created_at: Time.current,
        metadata: { record_count: 150 }
      )

      report_content = "Month,Income,Expenses\nJanuary,5000,3000"

      ScheduledReportMailer.with(
        scheduled_report: scheduled_report,
        run: run,
        report_content: report_content
      ).report_email
    end
  end
  ```

### 4.5 Phase 5: CRUD Controllers & Routes

**Justification:** Implements spec section 3.5 (API Design). Enables user management of scheduled reports.

**Tasks:**

- [ ] Add routes in `config/routes.rb`
  ```ruby
  resources :scheduled_reports do
    member do
      post :trigger    # Manual execution
      patch :toggle    # Enable/disable
    end

    resources :runs, only: [:index, :show], controller: "scheduled_report_runs"
  end
  ```

- [ ] Create `ScheduledReportsController` in `app/controllers/scheduled_reports_controller.rb`
  - Follow pattern from existing controllers (e.g., `AccountsController`)
  - Use `before_action :set_scheduled_report` for member actions
  - Scope queries to `Current.family.scheduled_reports`
  - Implement standard CRUD actions: `index`, `show`, `new`, `create`, `edit`, `update`, `destroy`
  - Implement custom actions: `trigger`, `toggle`
  - Use strong parameters for `scheduled_report_params`
  - Handle errors with flash messages
  - Redirect to index after create/update/destroy

- [ ] Create `ScheduledReportRunsController` in `app/controllers/scheduled_report_runs_controller.rb`
  - Read-only controller for viewing run history
  - Implement `index` action (list of runs for a scheduled report)
  - Implement `show` action (individual run details with download link)
  - Scope to parent scheduled report
  - Include pagination for run history (use `pagy` gem pattern if available)

- [ ] Add controller concern for authentication in controllers
  ```ruby
  # In both controllers
  before_action :authenticate_user!
  before_action :set_scheduled_report, only: [:show, :edit, :update, :destroy, :trigger, :toggle]

  private

  def set_scheduled_report
    @scheduled_report = Current.family.scheduled_reports.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to scheduled_reports_path, alert: t(".not_found")
  end

  def scheduled_report_params
    params.require(:scheduled_report).permit(
      :name,
      :report_type,
      :frequency,
      :delivery_method,
      :enabled,
      recipients: [],
      preferences: {}
    )
  end
  ```

- [ ] Write controller tests in `test/controllers/scheduled_reports_controller_test.rb`
  - Test all CRUD actions
  - Test access control (only family members can access)
  - Test `trigger` action enqueues job
  - Test `toggle` action updates enabled status
  - Test validation errors display correctly
  - Follow existing controller test patterns from `test/controllers/accounts_controller_test.rb`

- [ ] Write controller tests in `test/controllers/scheduled_report_runs_controller_test.rb`
  - Test index shows runs for scheduled report
  - Test show displays run details
  - Test download link works for attached files
  - Test pagination if implemented

### 4.6 Phase 6: User Interface

**Justification:** Implements spec section 3.6 (UI Components). User-facing interface for managing scheduled reports.

**Tasks:**

- [ ] Create index view in `app/views/scheduled_reports/index.html.erb`
  - Table displaying: Name, Type, Frequency, Last Run, Next Run, Status, Actions
  - Status badge component (success/failed/pending)
  - Enable/disable toggle using Stimulus controller
  - Edit, Delete, Trigger action buttons
  - "New Scheduled Report" button prominently displayed
  - Empty state if no scheduled reports exist
  - Follow existing table patterns from accounts or transactions index views
  - Use design system tokens (refer to `app/assets/tailwind/maybe-design-system.css`)

- [ ] Create show view in `app/views/scheduled_reports/show.html.erb`
  - Display scheduled report details in card format
  - List of recent runs (last 10) with status and download links
  - Edit and Delete buttons
  - Manual trigger button
  - Follow existing detail page patterns (e.g., `app/views/accounts/show.html.erb`)

- [ ] Create form partial in `app/views/scheduled_reports/_form.html.erb`
  ```erb
  <%= form_with(model: scheduled_report, local: true) do |form| %>
    <% if scheduled_report.errors.any? %>
      <div class="error-messages">
        <h3><%= t(".errors_heading", count: scheduled_report.errors.count) %></h3>
        <ul>
          <% scheduled_report.errors.full_messages.each do |message| %>
            <li><%= message %></li>
          <% end %>
        </ul>
      </div>
    <% end %>

    <div class="field">
      <%= form.label :name %>
      <%= form.text_field :name, required: true, maxlength: 100 %>
    </div>

    <div class="field">
      <%= form.label :report_type %>
      <%= form.select :report_type,
          ScheduledReport.report_types.keys.map { |type| [type.humanize, type] },
          { include_blank: t(".select_report_type") }
      %>
    </div>

    <div class="field">
      <%= form.label :frequency %>
      <%= form.select :frequency,
          ScheduledReport.frequencies.keys.map { |freq| [freq.humanize, freq] },
          { include_blank: t(".select_frequency") }
      %>
    </div>

    <div class="field">
      <%= form.label :delivery_method %>
      <%= form.select :delivery_method,
          ScheduledReport.delivery_methods.keys.map { |method| [method.humanize, method] },
          { include_blank: t(".select_delivery") }
      %>
    </div>

    <div class="field" data-controller="email-recipients">
      <%= form.label :recipients %>
      <%= form.text_area :recipients,
          value: scheduled_report.recipients.join("\n"),
          placeholder: t(".recipients_placeholder"),
          data: { email_recipients_target: "input" }
      %>
      <p class="help-text"><%= t(".recipients_help") %></p>
    </div>

    <div class="field">
      <%= form.label :enabled %>
      <%= form.check_box :enabled %>
    </div>

    <div class="actions">
      <%= form.submit t(".submit"), class: "btn btn-primary" %>
      <%= link_to t(".cancel"), scheduled_reports_path, class: "btn btn-secondary" %>
    </div>
  <% end %>
  ```

- [ ] Create new view in `app/views/scheduled_reports/new.html.erb`
  - Render form partial
  - Page heading and breadcrumbs
  - Follow existing form page patterns

- [ ] Create edit view in `app/views/scheduled_reports/edit.html.erb`
  - Render form partial
  - Page heading with scheduled report name
  - Delete button with confirmation
  - Follow existing edit page patterns

- [ ] Create Stimulus controller for toggle in `app/javascript/controllers/scheduled_report_toggle_controller.js`
  ```javascript
  import { Controller } from "@hotwired/stimulus"

  export default class extends Controller {
    static targets = ["switch"]
    static values = { url: String }

    async toggle(event) {
      const enabled = event.target.checked

      try {
        const response = await fetch(this.urlValue, {
          method: "PATCH",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": document.querySelector("[name='csrf-token']").content
          },
          body: JSON.stringify({ enabled })
        })

        if (!response.ok) {
          throw new Error("Failed to toggle scheduled report")
        }

        // Show success feedback
        this.showFlash("success", "Scheduled report updated")
      } catch (error) {
        // Revert toggle on error
        event.target.checked = !enabled
        this.showFlash("error", error.message)
      }
    }

    showFlash(type, message) {
      // Follow existing flash message pattern from application
    }
  }
  ```

- [ ] Create status badge component in `app/components/scheduled_report_status_component.rb`
  ```ruby
  class ScheduledReportStatusComponent < ViewComponent::Base
    def initialize(scheduled_report:)
      @scheduled_report = scheduled_report
    end

    def status
      if @scheduled_report.last_error.present?
        :failed
      elsif @scheduled_report.last_success_at.present?
        :success
      else
        :pending
      end
    end

    def badge_class
      case status
      when :success
        "badge badge-success"
      when :failed
        "badge badge-error"
      when :pending
        "badge badge-warning"
      end
    end

    def status_text
      case status
      when :success
        t(".success")
      when :failed
        t(".failed")
      when :pending
        t(".pending")
      end
    end
  end
  ```

- [ ] Create status badge template in `app/components/scheduled_report_status_component.html.erb`
  ```erb
  <span class="<%= badge_class %>" title="<%= @scheduled_report.last_error %>">
    <%= status_text %>
  </span>
  ```

- [ ] Add navigation link
  - Add link to scheduled reports in settings or reports navigation
  - Include badge showing count of failed reports (if any)
  - Reference existing navigation patterns in `app/views/layouts/application.html.erb`

- [ ] Add localization in `config/locales/views/scheduled_reports.en.yml`
  - All user-facing strings for views
  - Form labels, placeholders, help text
  - Button text, headings, empty states
  - Flash messages (success, error)
  - Follow i18n patterns from existing locale files

- [ ] Create component tests if using ViewComponent
  - Test status badge displays correctly for each state
  - Follow existing component test patterns

### 4.7 Phase 7: Testing & Documentation

**Justification:** Validation and documentation requirements. Ensures feature works end-to-end and is documented for users.

**Tasks:**

- [ ] Write system test in `test/system/scheduled_reports_test.rb`
  ```ruby
  require "application_system_test_case"

  class ScheduledReportsTest < ApplicationSystemTestCase
    setup do
      sign_in users(:dylan)
    end

    test "creating a new scheduled report" do
      visit scheduled_reports_path
      click_on "New Scheduled Report"

      fill_in "Name", with: "My Monthly Report"
      select "Income Expense", from: "Report type"
      select "Monthly", from: "Frequency"
      select "Email", from: "Delivery method"
      fill_in "Recipients", with: "test@example.com"

      assert_difference "ScheduledReport.count", 1 do
        click_button "Create Scheduled Report"
      end

      assert_text "Scheduled report was successfully created"
      assert_text "My Monthly Report"
    end

    test "manually triggering a scheduled report" do
      scheduled_report = scheduled_reports(:monthly_income_expense)

      visit scheduled_report_path(scheduled_report)

      assert_enqueued_jobs 1, only: GenerateScheduledReportJob do
        click_button "Generate Now"
      end

      assert_text "Report generation started"
    end

    test "toggling a scheduled report on/off" do
      scheduled_report = scheduled_reports(:monthly_income_expense)

      visit scheduled_reports_path

      # Disable
      within "#scheduled_report_#{scheduled_report.id}" do
        find(".toggle-switch").click
      end

      scheduled_report.reload
      assert_not scheduled_report.enabled?

      # Re-enable
      within "#scheduled_report_#{scheduled_report.id}" do
        find(".toggle-switch").click
      end

      scheduled_report.reload
      assert scheduled_report.enabled?
    end
  end
  ```

- [ ] Write integration test for full workflow in `test/integration/scheduled_report_generation_test.rb`
  ```ruby
  require "test_helper"

  class ScheduledReportGenerationTest < ActionDispatch::IntegrationTest
    setup do
      @family = families(:dylan_family)
      @user = users(:dylan)
      sign_in @user
    end

    test "complete workflow from creation to email delivery" do
      # Create scheduled report
      scheduled_report = @family.scheduled_reports.create!(
        user: @user,
        name: "Test Report",
        report_type: :income_expense,
        frequency: :monthly,
        delivery_method: :email,
        recipients: ["test@example.com"]
      )

      assert scheduled_report.due?

      # Process scheduled reports
      assert_emails 1 do
        perform_enqueued_jobs do
          ProcessScheduledReportsJob.perform_now
        end
      end

      # Verify run was created and marked successful
      run = scheduled_report.scheduled_report_runs.last
      assert run.completed?

      # Verify scheduled report was updated
      scheduled_report.reload
      assert scheduled_report.last_success_at.present?
      assert scheduled_report.next_run_at > Time.current
    end
  end
  ```

- [ ] Run full test suite: `bin/rails test`
- [ ] Run system tests: `bin/rails test:system`
- [ ] Run linting: `bin/rubocop -f github -a`
- [ ] Run security check: `bin/brakeman --no-pager`

- [ ] Create user documentation in `docs/features/scheduled-reports.md`
  - Overview of scheduled reports feature
  - How to create a scheduled report
  - Report type descriptions
  - Frequency options explained
  - Delivery method options
  - Managing scheduled reports (edit, disable, delete)
  - Viewing run history
  - Troubleshooting common issues
  - Include screenshots (if applicable)

- [ ] Add inline help text in UI
  - Tooltips for complex fields
  - Help icons linking to documentation
  - Placeholder text for form inputs
  - Error messages that guide users to resolution

- [ ] Update changelog or release notes
  - Add scheduled reports feature to upcoming release notes
  - Highlight key capabilities
  - Note any configuration requirements

---

## Additional Considerations

### Performance Optimization
- Add database indexes for common queries (already included in migrations)
- Consider pagination for large run history lists
- Implement report caching for frequently generated reports
- Monitor job queue performance under load

### Security
- Validate email recipients to prevent spam
- Rate limit manual trigger action (prevent abuse)
- Ensure proper scoping to Current.family throughout
- Sanitize report data before email delivery

### Future Enhancements (Not in Scope)
- Support for custom date ranges in preferences
- PDF report format (currently CSV only)
- Report templates (saved preference configurations)
- Share reports with external stakeholders
- API endpoints for programmatic access
- Webhook delivery option
- Slack/Discord integration for notifications
- Report comparison (e.g., month-over-month)

---

**End of Implementation Plan**
