# Net Worth Timeline - Implementation Plan

## Overview
A visual timeline showing net worth progression over time with historical snapshots and trends. Aggregates all account balances (assets - liabilities) at different points in time to show total net worth evolution.

**Key Components:**
- Backend: Net worth calculation service, controller endpoint, balance aggregation queries
- Frontend: Time series chart visualization using existing D3.js infrastructure
- Integration: Leverages existing Balance model and time series chart patterns

**Sequencing Logic:**
1. Backend data layer (model/service for net worth calculations)
2. Controller and API endpoint
3. Frontend view and chart integration
4. Testing and validation
5. i18n and documentation

---

## Table of Contents
1. [Phase 1: Backend - Net Worth Calculation Service](#phase-1)
2. [Phase 2: Controller and Routes](#phase-2)
3. [Phase 3: Frontend - View and Chart Integration](#phase-3)
4. [Phase 4: Testing](#phase-4)
5. [Phase 5: i18n and Documentation](#phase-5)

---

## Phase 1: Backend - Net Worth Calculation Service {#phase-1}

**Justification:** Foundation for net worth calculations. Establishes the core business logic for aggregating account balances over time following the "Skinny Controllers, Fat Models" convention.

### 1.1 Create Net Worth Service

- [ ] Create `app/models/net_worth.rb` service class

**Novel Implementation - Full Detail Required:**

```ruby
# app/models/net_worth.rb

# Calculates net worth (assets - liabilities) for a family over time.
# Provides time-series data suitable for charting and trend analysis.
#
# @example Basic usage
#   net_worth = NetWorth.new(family)
#   series = net_worth.series(period: period)
#   current = net_worth.calculate(date: Date.current)
#
# @example With date range
#   net_worth = NetWorth.new(family)
#   timeline = net_worth.timeline(
#     start_date: 1.year.ago,
#     end_date: Date.current,
#     interval: :monthly
#   )
class NetWorth
  attr_reader :family

  # Supported time intervals for timeline generation
  INTERVALS = [:daily, :weekly, :monthly, :quarterly, :yearly].freeze

  # @param family [Family] The family to calculate net worth for
  def initialize(family)
    @family = family
  end

  # Calculate net worth at a specific date
  #
  # @param date [Date] The date to calculate net worth for (defaults to today)
  # @return [Money] Net worth as a Money object in family's currency
  #
  # @note This method aggregates all account balances (assets - liabilities)
  #   at the specified date. For accounts without a balance record at the exact
  #   date, it uses the most recent balance before that date.
  def calculate(date: Date.current)
    asset_total = calculate_total_for_classification(:asset, date: date)
    liability_total = calculate_total_for_classification(:liability, date: date)

    asset_total - liability_total
  end

  # Generate a time series of net worth values over a period
  #
  # @param period [Period] The period to generate series for
  # @param interval [Symbol] Time interval (:daily, :weekly, :monthly, :quarterly, :yearly)
  # @return [Series] A Series object containing date/value pairs suitable for charting
  #
  # @note This is the primary method for generating chart data. It creates
  #   data points at regular intervals within the period.
  def series(period:, interval: :daily)
    raise ArgumentError, "Invalid interval: #{interval}" unless INTERVALS.include?(interval)

    dates = generate_dates_for_interval(
      start_date: period.date_range.first,
      end_date: period.date_range.last,
      interval: interval
    )

    values = dates.map do |date|
      {
        date: date,
        value: calculate(date: date)
      }
    end

    Series.new(values, trend_color: trend_color_for_period(period))
  end

  # Generate a detailed timeline with additional metadata
  #
  # @param start_date [Date] Timeline start date
  # @param end_date [Date] Timeline end date
  # @param interval [Symbol] Time interval between data points
  # @return [Hash] Hash containing timeline data with trends and comparisons
  #
  # @example Return structure
  #   {
  #     data_points: [{ date: Date, value: Money, change: Money, percent_change: Float }, ...],
  #     summary: { start_value: Money, end_value: Money, total_change: Money, percent_change: Float },
  #     interval: :monthly
  #   }
  def timeline(start_date:, end_date:, interval: :monthly)
    raise ArgumentError, "Invalid interval: #{interval}" unless INTERVALS.include?(interval)
    raise ArgumentError, "Start date must be before end date" if start_date > end_date

    dates = generate_dates_for_interval(
      start_date: start_date,
      end_date: end_date,
      interval: interval
    )

    # Calculate values for each date
    data_points = []
    previous_value = nil

    dates.each do |date|
      current_value = calculate(date: date)

      change = previous_value ? current_value - previous_value : Money.new(0, family.currency)
      percent_change = if previous_value && !previous_value.zero?
        ((current_value - previous_value) / previous_value * 100).round(2)
      else
        0.0
      end

      data_points << {
        date: date,
        value: current_value,
        change: change,
        percent_change: percent_change
      }

      previous_value = current_value
    end

    # Calculate summary statistics
    start_value = data_points.first[:value]
    end_value = data_points.last[:value]
    total_change = end_value - start_value
    overall_percent_change = if !start_value.zero?
      ((end_value - start_value) / start_value * 100).round(2)
    else
      0.0
    end

    {
      data_points: data_points,
      summary: {
        start_value: start_value,
        end_value: end_value,
        total_change: total_change,
        percent_change: overall_percent_change
      },
      interval: interval
    }
  end

  # Get current net worth (convenience method)
  #
  # @return [Money] Current net worth
  def current
    calculate(date: Date.current)
  end

  private

    # Calculate total balance for a specific classification (asset or liability)
    #
    # @param classification [Symbol] :asset or :liability
    # @param date [Date] The date to calculate for
    # @return [Money] Total balance in family's currency
    #
    # @note This method:
    #   1. Finds all accounts with the given classification
    #   2. For each account, finds the most recent balance at or before the date
    #   3. Converts to family currency if needed
    #   4. Sums all balances
    def calculate_total_for_classification(classification, date:)
      accounts = family.accounts
        .visible
        .where(classification: classification)

      total = Money.new(0, family.currency)

      accounts.find_each do |account|
        balance = most_recent_balance_for_account(account, date: date)
        next unless balance

        # Convert to family currency if account uses different currency
        balance_money = if account.currency == family.currency
          Money.new(balance, family.currency)
        else
          convert_to_family_currency(balance, from_currency: account.currency, date: date)
        end

        total += balance_money
      end

      total
    end

    # Find the most recent balance for an account at or before a date
    #
    # @param account [Account] The account to find balance for
    # @param date [Date] The target date
    # @return [BigDecimal, nil] The balance value, or nil if no balance found
    #
    # @note If no balance record exists at or before the date, returns nil
    def most_recent_balance_for_account(account, date:)
      balance_record = account.balances
        .where("date <= ?", date)
        .order(date: :desc)
        .first

      return nil unless balance_record

      # Use end_balance if available (it's the calculated balance including flows)
      # Otherwise fall back to balance field
      balance_record.end_balance || balance_record.balance
    end

    # Convert amount to family's currency using historical exchange rate
    #
    # @param amount [BigDecimal] Amount to convert
    # @param from_currency [String] Source currency code
    # @param date [Date] Date for exchange rate lookup
    # @return [Money] Converted amount in family currency
    #
    # @note Uses ExchangeRate model for historical rates. Falls back to
    #   current rate if historical rate is unavailable.
    def convert_to_family_currency(amount, from_currency:, date:)
      return Money.new(amount, family.currency) if from_currency == family.currency

      rate = ExchangeRate.find_rate(
        from: from_currency,
        to: family.currency,
        date: date
      )

      converted_amount = rate ? (amount * rate) : amount
      Money.new(converted_amount, family.currency)
    end

    # Generate array of dates based on interval
    #
    # @param start_date [Date] Start of range
    # @param end_date [Date] End of range
    # @param interval [Symbol] Time interval
    # @return [Array<Date>] Array of dates at the specified interval
    #
    # @note For monthly/quarterly/yearly intervals, uses end of period
    #   (e.g., end of month) to capture full period data
    def generate_dates_for_interval(start_date:, end_date:, interval:)
      dates = []
      current_date = start_date

      case interval
      when :daily
        while current_date <= end_date
          dates << current_date
          current_date += 1.day
        end
      when :weekly
        while current_date <= end_date
          dates << current_date
          current_date += 1.week
        end
      when :monthly
        # Use end of month for monthly data points
        while current_date <= end_date
          dates << [current_date.end_of_month, end_date].min
          current_date = current_date.next_month.beginning_of_month
        end
      when :quarterly
        # Use end of quarter for quarterly data points
        while current_date <= end_date
          dates << [current_date.end_of_quarter, end_date].min
          current_date = (current_date.end_of_quarter + 1.day).beginning_of_quarter
        end
      when :yearly
        # Use end of year for yearly data points
        while current_date <= end_date
          dates << [current_date.end_of_year, end_date].min
          current_date = current_date.next_year.beginning_of_year
        end
      end

      dates.uniq
    end

    # Determine trend color based on period performance
    #
    # @param period [Period] The period to evaluate
    # @return [String] CSS color variable name
    #
    # @note Green if net worth increased, red if decreased, gray if unchanged
    def trend_color_for_period(period)
      start_value = calculate(date: period.date_range.first)
      end_value = calculate(date: period.date_range.last)

      if end_value > start_value
        "var(--color-success)"
      elsif end_value < start_value
        "var(--color-destructive)"
      else
        "var(--color-gray-500)"
      end
    end
end
```

- [ ] Add test for NetWorth service in `test/models/net_worth_test.rb`

**Novel Testing Logic - Full Detail Required:**

```ruby
# test/models/net_worth_test.rb
require "test_helper"

class NetWorthTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @net_worth = NetWorth.new(@family)

    # Create test accounts with balances
    @checking = accounts(:checking)
    @savings = accounts(:savings)
    @credit_card = accounts(:credit_card)

    # Freeze time for consistent testing
    travel_to Date.new(2024, 1, 15)
  end

  teardown do
    travel_back
  end

  test "calculates current net worth as assets minus liabilities" do
    # Create balance records
    Balance.create!(
      account: @checking,
      date: Date.current,
      balance: 5000,
      end_balance: 5000
    )

    Balance.create!(
      account: @savings,
      date: Date.current,
      balance: 10000,
      end_balance: 10000
    )

    Balance.create!(
      account: @credit_card,
      date: Date.current,
      balance: 2000,
      end_balance: 2000
    )

    net_worth = @net_worth.calculate(date: Date.current)

    # (5000 + 10000) assets - 2000 liabilities = 13000
    assert_equal Money.new(13000, @family.currency), net_worth
  end

  test "uses most recent balance when exact date not available" do
    Balance.create!(
      account: @checking,
      date: Date.new(2024, 1, 1),
      balance: 5000,
      end_balance: 5000
    )

    # Calculate for a date after the balance record
    net_worth = @net_worth.calculate(date: Date.new(2024, 1, 10))

    # Should use the balance from Jan 1
    assert net_worth.cents > 0
  end

  test "generates monthly series for a period" do
    period = Period.custom(start_date: Date.new(2024, 1, 1), end_date: Date.new(2024, 3, 31))

    series = @net_worth.series(period: period, interval: :monthly)

    assert_instance_of Series, series
    # Should have 3 data points (one per month)
    assert_equal 3, series.values.length
  end

  test "timeline includes change and percent change" do
    # Create balances for testing trend
    Balance.create!(account: @checking, date: Date.new(2024, 1, 1), balance: 5000, end_balance: 5000)
    Balance.create!(account: @checking, date: Date.new(2024, 2, 1), balance: 6000, end_balance: 6000)

    timeline = @net_worth.timeline(
      start_date: Date.new(2024, 1, 1),
      end_date: Date.new(2024, 2, 1),
      interval: :monthly
    )

    assert_includes timeline, :data_points
    assert_includes timeline, :summary
    assert_equal :monthly, timeline[:interval]

    # Summary should show increase
    assert timeline[:summary][:total_change] > Money.new(0, @family.currency)
  end

  test "raises error for invalid interval" do
    period = Period.custom(start_date: Date.current, end_date: Date.current + 1.month)

    assert_raises(ArgumentError) do
      @net_worth.series(period: period, interval: :invalid)
    end
  end

  test "handles accounts with different currencies" do
    # Reference existing multi-currency test pattern from account_test.rb
    # Standard pattern - just verify it works with currency conversion
    skip "Implement after ExchangeRate integration is confirmed"
  end
end
```

---

## Phase 2: Controller and Routes {#phase-2}

**Justification:** Exposes net worth data via RESTful endpoint. Follows existing reports controller patterns for consistency.

### 2.1 Add Net Worth Endpoint to Reports Controller

- [ ] Add `net_worth` action to `app/controllers/reports_controller.rb`

**Standard Pattern - Reference Existing:**

Follow the pattern from `ReportsController#index` (app/controllers/reports_controller.rb:9-44):
- Use `include Periodable` concern for period parsing
- Parse period parameters (start_date, end_date, interval)
- Instantiate `NetWorth.new(Current.family)`
- Generate series data
- Store in instance variables for view

**Differences from existing pattern:**
- New action specifically for net worth timeline
- Returns net worth series data instead of income/expense totals
- Supports interval parameter for granularity

```ruby
# Add to app/controllers/reports_controller.rb

def net_worth
  @period_type = params[:period_type]&.to_sym || :monthly
  @start_date = parse_date_param(:start_date) || 1.year.ago.to_date
  @end_date = parse_date_param(:end_date) || Date.current
  @interval = params[:interval]&.to_sym || :monthly

  validate_and_fix_date_range(show_flash: true)

  @net_worth = NetWorth.new(Current.family)
  @timeline = @net_worth.timeline(
    start_date: @start_date,
    end_date: @end_date,
    interval: @interval
  )

  @current_net_worth = @net_worth.current

  @breadcrumbs = [
    ["Home", root_path],
    ["Reports", reports_path],
    ["Net Worth Timeline", nil]
  ]
end
```

### 2.2 Add Routes

- [ ] Add routes in `config/routes.rb`

**Standard Pattern:**

```ruby
# In resources :reports block
resources :reports, only: [:index] do
  collection do
    get :net_worth
    get :export_transactions
    get :google_sheets_instructions
    post :update_preferences
  end
end
```

---

## Phase 3: Frontend - View and Chart Integration {#phase-3}

**Justification:** Provides user interface for viewing net worth timeline using established Hotwire and D3.js patterns.

### 3.1 Create Net Worth View

- [ ] Create `app/views/reports/net_worth.html.erb`

**Standard Pattern - Reference Existing:**

Follow the structure from `app/views/reports/index.html.erb`:
- Breadcrumb navigation
- Period selector component (use existing partial)
- Time series chart with D3.js controller
- Summary metrics cards
- Use Tailwind design system tokens

```erb
<%# app/views/reports/net_worth.html.erb %>
<div class="space-y-6">
  <%# Breadcrumbs %>
  <%= render "shared/breadcrumbs", breadcrumbs: @breadcrumbs %>

  <%# Header %>
  <div class="flex items-center justify-between">
    <h1 class="text-2xl font-bold text-primary"><%= t("reports.net_worth.title") %></h1>
  </div>

  <%# Period Selector %>
  <%= render "reports/period_selector",
      period_type: @period_type,
      start_date: @start_date,
      end_date: @end_date,
      interval: @interval %>

  <%# Summary Cards %>
  <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
    <div class="bg-container border border-primary rounded-lg p-6">
      <h3 class="text-sm font-medium text-subdued"><%= t("reports.net_worth.current_value") %></h3>
      <p class="text-3xl font-bold text-primary mt-2">
        <%= @current_net_worth.format %>
      </p>
    </div>

    <div class="bg-container border border-primary rounded-lg p-6">
      <h3 class="text-sm font-medium text-subdued"><%= t("reports.net_worth.period_change") %></h3>
      <p class="text-3xl font-bold <%= @timeline[:summary][:total_change] >= 0 ? 'text-success' : 'text-destructive' %> mt-2">
        <%= @timeline[:summary][:total_change].format %>
      </p>
    </div>

    <div class="bg-container border border-primary rounded-lg p-6">
      <h3 class="text-sm font-medium text-subdued"><%= t("reports.net_worth.percent_change") %></h3>
      <p class="text-3xl font-bold <%= @timeline[:summary][:percent_change] >= 0 ? 'text-success' : 'text-destructive' %> mt-2">
        <%= number_to_percentage(@timeline[:summary][:percent_change], precision: 1) %>
      </p>
    </div>
  </div>

  <%# Chart %>
  <div class="bg-container border border-primary rounded-lg p-6">
    <div
      data-controller="time-series-chart"
      data-time-series-chart-data-value="<%= chart_data_for_net_worth(@timeline).to_json %>"
      data-time-series-chart-use-labels-value="true"
      data-time-series-chart-use-tooltip-value="true"
      class="h-96">
    </div>
  </div>
</div>
```

### 3.2 Add Helper Method for Chart Data

- [ ] Add helper method in `app/helpers/reports_helper.rb`

**Novel Helper - Full Detail Required:**

```ruby
# app/helpers/reports_helper.rb

# Transform net worth timeline data into format expected by time series chart controller
#
# @param timeline [Hash] Timeline hash from NetWorth#timeline method
# @return [Hash] Chart-ready data structure
#
# @example Output format
#   {
#     values: [
#       { date: "2024-01-31", date_formatted: "Jan 31, 2024", value: { amount: "15000.00", formatted: "$15,000.00" }, trend: {...} },
#       ...
#     ],
#     trend: { color: "var(--color-success)" }
#   }
def chart_data_for_net_worth(timeline)
  values = timeline[:data_points].map.with_index do |point, index|
    previous_value = index > 0 ? timeline[:data_points][index - 1][:value] : point[:value]

    {
      date: point[:date].strftime("%Y-%m-%d"),
      date_formatted: l(point[:date], format: :long),
      value: {
        amount: point[:value].to_s,
        formatted: point[:value].format
      },
      trend: {
        current: {
          amount: point[:value].to_s,
          formatted: point[:value].format
        },
        previous: {
          amount: previous_value.to_s,
          formatted: previous_value.format
        },
        value: point[:change].to_s,
        percent_formatted: number_to_percentage(point[:percent_change], precision: 1),
        color: point[:change] >= 0 ? "var(--color-success)" : "var(--color-destructive)"
      }
    }
  end

  overall_trend_color = if timeline[:summary][:total_change] >= 0
    "var(--color-success)"
  else
    "var(--color-destructive)"
  end

  {
    values: values,
    trend: { color: overall_trend_color }
  }
end
```

### 3.3 Add Navigation Link

- [ ] Add link to net worth timeline in reports navigation
- [ ] Update `app/views/reports/index.html.erb` or reports navigation partial

**Standard Pattern:**

```erb
<%= link_to net_worth_reports_path,
    class: "flex items-center gap-2 px-4 py-2 rounded-lg hover:bg-gray-100" do %>
  <%= icon "trending-up", class: "w-5 h-5" %>
  <span><%= t("reports.net_worth.nav_title") %></span>
<% end %>
```

---

## Phase 4: Testing {#phase-4}

**Justification:** Ensures reliability and correctness of net worth calculations and UI.

### 4.1 Controller Tests

- [ ] Add controller test in `test/controllers/reports_controller_test.rb`

**Standard Pattern - Reference Existing:**

Follow test patterns from `test/controllers/reports_controller_test.rb`:

```ruby
test "should get net worth timeline" do
  get net_worth_reports_url
  assert_response :success
  assert_not_nil assigns(:net_worth)
  assert_not_nil assigns(:timeline)
  assert_not_nil assigns(:current_net_worth)
end

test "net worth respects period parameters" do
  get net_worth_reports_url, params: {
    start_date: "2024-01-01",
    end_date: "2024-12-31",
    interval: "monthly"
  }
  assert_response :success
  assert_equal Date.parse("2024-01-01"), assigns(:start_date)
  assert_equal Date.parse("2024-12-31"), assigns(:end_date)
  assert_equal :monthly, assigns(:interval)
end
```

### 4.2 System Test (Optional - Visual Verification)

- [ ] Create system test in `test/system/net_worth_timeline_test.rb` (only if complex interactions need verification)

**Standard Pattern:**

```ruby
require "application_system_test_case"

class NetWorthTimelineTest < ApplicationSystemTestCase
  test "displays net worth chart" do
    sign_in users(:family_admin)

    visit net_worth_reports_path

    assert_selector "h1", text: "Net Worth Timeline"
    assert_selector "[data-controller='time-series-chart']"
  end
end
```

---

## Phase 5: i18n and Documentation {#phase-5}

**Justification:** Ensures feature is properly internationalized and documented for maintainability.

### 5.1 Add i18n Translations

- [ ] Add translations to `config/locales/en.yml`

```yaml
en:
  reports:
    net_worth:
      title: "Net Worth Timeline"
      nav_title: "Net Worth"
      current_value: "Current Net Worth"
      period_change: "Period Change"
      percent_change: "% Change"
      description: "Track your total net worth over time (assets minus liabilities)"
      intervals:
        daily: "Daily"
        weekly: "Weekly"
        monthly: "Monthly"
        quarterly: "Quarterly"
        yearly: "Yearly"
```

### 5.2 Update CHANGELOG

- [ ] Add entry to `CHANGELOG.md`

```markdown
## [Unreleased]

### Added
- Net Worth Timeline: Visual timeline showing net worth progression over time
  - Aggregates all account balances (assets - liabilities) at different points in time
  - Supports multiple time intervals (daily, weekly, monthly, quarterly, yearly)
  - Interactive D3.js chart with hover tooltips showing detailed information
  - Summary metrics showing current value, period change, and percentage change
```

### 5.3 Add Feature Documentation

- [ ] Create or update user guide documentation (if docs/ directory exists)

**Standard Pattern:**

Reference existing docs structure. Document:
- How to access net worth timeline
- What data is included in calculations
- How to adjust time periods and intervals
- How to interpret the chart

---

## Validation Steps

After implementing all phases, verify:

- [ ] Navigate to Reports > Net Worth Timeline
- [ ] Verify chart displays correctly with family's account data
- [ ] Test different time periods (1 month, 6 months, 1 year, custom)
- [ ] Test different intervals (daily, weekly, monthly)
- [ ] Verify summary metrics match calculated values
- [ ] Hover over chart points and verify tooltip data
- [ ] Test with accounts in different currencies
- [ ] Test with no data (should show empty state)
- [ ] Verify all text is properly internationalized
- [ ] Run full test suite: `bin/rails test`
- [ ] Check for N+1 queries with Bullet gem
