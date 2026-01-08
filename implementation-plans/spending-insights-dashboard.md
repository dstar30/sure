# Spending Insights Dashboard - Implementation Plan

## Table of Contents

1. [Overview](#1-overview)
2. [Requirements](#2-requirements)
   - 2.1 [User Needs](#21-user-needs)
   - 2.2 [Functional Requirements](#22-functional-requirements)
   - 2.3 [Non-Functional Requirements](#23-non-functional-requirements)
3. [Technical Specification](#3-technical-specification)
   - 3.1 [Data Model](#31-data-model)
   - 3.2 [Insight Types](#32-insight-types)
   - 3.3 [Analytics Engine](#33-analytics-engine)
   - 3.4 [Calculation Algorithms](#34-calculation-algorithms)
   - 3.5 [UI Components](#35-ui-components)
4. [Implementation Plan](#4-implementation-plan)
   - 4.1 [Phase 1: Prerequisites & Data Foundation](#41-phase-1-prerequisites--data-foundation)
   - 4.2 [Phase 2: Core Insight Infrastructure](#42-phase-2-core-insight-infrastructure)
   - 4.3 [Phase 3: Comparison Insights](#43-phase-3-comparison-insights)
   - 4.4 [Phase 4: Anomaly Detection](#44-phase-4-anomaly-detection)
   - 4.5 [Phase 5: Trend Analysis](#45-phase-5-trend-analysis)
   - 4.6 [Phase 6: Pattern Detection](#46-phase-6-pattern-detection)
   - 4.7 [Phase 7: Reports Dashboard Integration](#47-phase-7-reports-dashboard-integration)
   - 4.8 [Phase 8: Category Trend Visualization](#48-phase-8-category-trend-visualization)
   - 4.9 [Phase 9: Testing & Documentation](#49-phase-9-testing--documentation)

---

## 1. Overview

**What We're Building:**
A spending insights dashboard that automatically analyzes spending patterns and surfaces actionable insights like "You spent 20% more on dining this month" with category trend analysis and anomaly detection. The dashboard helps users understand their spending behavior through intelligent comparison, trend, and pattern analysis.

**Key Components:**
- Insight generation engine using existing `IncomeStatement` and `CategoryStats` infrastructure
- Four insight types: comparison, anomaly, trend, and pattern
- On-demand calculation when viewing Reports dashboard
- Card-based UI integrated into existing Reports section
- Interactive category trend charts with anomaly markers
- Configurable thresholds (20% for significant changes)

**Sequencing Logic:**
1. **Foundation first** - Validate existing analytics infrastructure
2. **Core infrastructure** - Base models and service layer
3. **Incremental insight types** - Build each type separately (comparison → anomaly → trend → pattern)
4. **UI integration** - Add to Reports dashboard with card components
5. **Visualization** - Enhanced charts for trend display
6. **Testing & docs** - Comprehensive validation

**Key Design Decisions:**
- Leverage existing `IncomeStatement`, `CategoryStats`, `Trend` models (no reinvention)
- On-demand generation (calculate when user views dashboard, cache for session)
- 3-month median baseline for anomaly detection
- 20% variance threshold for significance
- Integrate into Reports controller/views (not main dashboard)

---

## 2. Requirements

### 2.1 User Needs

**Primary User Stories:**
- As a user, I want to see how my spending this month compares to last month
- As a user, I want to be alerted when I'm spending unusually high amounts in a category
- As a user, I want to understand spending trends over the past several months
- As a user, I want to see if I have spending patterns (weekday vs weekend)
- As a user, I want actionable insights that help me make better financial decisions

**Secondary User Stories:**
- As a user, I want to see which categories are driving spending changes
- As a user, I want to click on an insight to see detailed transaction history
- As a user, I want insights to update based on the selected time period
- As a user, I want insights presented in plain language (not just raw numbers)

### 2.2 Functional Requirements

**FR-1: Comparison Insights**
- Calculate month-over-month spending changes per category
- Show percentage change with directional indicators (up/down)
- Highlight significant changes (≥20% variance)
- Display top 5 categories with largest changes
- Format: "You spent 20% more on Dining this month ($450 vs $375 last month)"

**FR-2: Anomaly Detection**
- Compare current month spending to 3-month median per category
- Flag categories with ≥20% deviation from median
- Distinguish between unusually high and unusually low spending
- Filter out categories with insufficient historical data (<3 months)
- Format: "Your Groceries spending is 25% higher than usual this month"

**FR-3: Trend Analysis**
- Calculate spending trends over last 3-6 months per category
- Identify increasing, decreasing, or stable trends
- Show trend direction with visual indicators
- Calculate rate of change (percentage increase/decrease per month)
- Format: "Your Transportation spending has increased 15% over the last 3 months"

**FR-4: Pattern Detection**
- Analyze weekday vs weekend spending patterns per category
- Calculate average spending differences
- Identify categories with significant weekday/weekend variance
- Format: "You spend 30% more on Dining on weekends"

**FR-5: Dashboard Integration**
- Add "Spending Insights" section to Reports dashboard
- Display insights as collapsible cards
- Support period filtering (current month, last 30 days, etc.)
- Show insights in priority order (anomalies → large changes → trends → patterns)
- Empty state when insufficient data for insights

**FR-6: Visualization**
- Category trend charts showing monthly spending over time
- Anomaly markers on charts (visual indicators for unusual months)
- Comparison overlays (current vs previous period)
- Interactive tooltips with detailed amounts

### 2.3 Non-Functional Requirements

**Performance:**
- Insight calculation should complete within 2 seconds for typical datasets
- Use existing `IncomeStatement` caching infrastructure
- Minimize database queries (use aggregation, not iteration)
- Cache calculated insights for session duration

**Accuracy:**
- Use precise monetary calculations (Money objects)
- Handle multi-currency scenarios correctly
- Respect transaction exclusions (transfers, one-time, etc.)
- Account for partial months (prorate comparisons)

**Usability:**
- Plain language insights (not technical jargon)
- Color-coded indicators (green=good, red=concerning)
- Mobile-responsive card layout
- Accessible (ARIA labels, keyboard navigation)

**Maintainability:**
- Reuse existing analytics infrastructure
- Follow existing controller/view patterns
- Modular insight generators (easy to add new types)
- Comprehensive test coverage

---

## 3. Technical Specification

### 3.1 Data Model

#### Insight Structure (Value Object)

**Not a database model** - calculated on-demand and cached in session/memory

```ruby
# Insight value object
Insight = Data.define(
  :type,              # :comparison, :anomaly, :trend, :pattern
  :category,          # Category object
  :message,           # Human-readable insight text
  :current_value,     # Money object for current period
  :comparison_value,  # Money object for comparison (previous/median)
  :change_percent,    # Percentage change (Float)
  :direction,         # :up, :down, :stable
  :sentiment,         # :positive, :negative, :neutral
  :metadata           # Hash with additional context
)
```

**Example Insight:**
```ruby
Insight.new(
  type: :comparison,
  category: dining_category,
  message: "You spent 20% more on Dining this month",
  current_value: Money.new(45000, "USD"),  # $450.00
  comparison_value: Money.new(37500, "USD"),  # $375.00
  change_percent: 20.0,
  direction: :up,
  sentiment: :negative,  # Increased expense = negative
  metadata: {
    current_period: "January 2024",
    comparison_period: "December 2023",
    transaction_count: 23
  }
)
```

### 3.2 Insight Types

#### Type 1: Comparison Insights

**Purpose:** Month-over-month spending changes

**Algorithm:**
1. Get current period expense totals by category (using `IncomeStatement#expense_totals`)
2. Get previous period expense totals by category
3. For each category, calculate: `(current - previous) / previous * 100`
4. Filter: Only include categories with ≥20% change
5. Sort: By absolute change amount (descending)
6. Return: Top 5 insights

**Threshold:** 20% variance

**Message Template:**
- Increase: "You spent {percent}% more on {category} this month ({current} vs {previous} last month)"
- Decrease: "You spent {percent}% less on {category} this month ({current} vs {previous} last month)"

#### Type 2: Anomaly Insights

**Purpose:** Detect unusual spending vs historical baseline

**Algorithm:**
1. Get current month expense totals by category
2. Get 3-month median spending per category (using `CategoryStats#median_expense`)
3. For each category, calculate: `(current - median) / median * 100`
4. Filter: Only include categories with ≥20% variance and ≥3 months of history
5. Sort: By absolute variance percentage (descending)
6. Return: Top 5 insights

**Threshold:** 20% variance from 3-month median

**Message Template:**
- Higher: "Your {category} spending is {percent}% higher than usual this month ({current} vs {median} median)"
- Lower: "Your {category} spending is {percent}% lower than usual this month ({current} vs {median} median)"

#### Type 3: Trend Insights

**Purpose:** Multi-month spending trends per category

**Algorithm:**
1. Get last 6 months of expense totals by category
2. For each category, calculate linear regression slope
3. Convert slope to percentage change per month
4. Filter: Only include categories with consistent trend (R² > 0.5) and ≥10% total change
5. Sort: By trend strength (R² value)
6. Return: Top 5 insights

**Threshold:** ≥10% total change over period, R² > 0.5 for consistency

**Message Template:**
- Increasing: "Your {category} spending has increased {percent}% over the last {months} months"
- Decreasing: "Your {category} spending has decreased {percent}% over the last {months} months"

#### Type 4: Pattern Insights

**Purpose:** Weekday vs weekend spending patterns

**Algorithm:**
1. Get all transactions for current period
2. Group by category, split into weekday (Mon-Fri) vs weekend (Sat-Sun)
3. Calculate average daily spending for weekday vs weekend
4. For each category, calculate: `(weekend_avg - weekday_avg) / weekday_avg * 100`
5. Filter: Only include categories with ≥20% difference and ≥10 transactions
6. Sort: By absolute difference percentage (descending)
7. Return: Top 5 insights

**Threshold:** 20% difference, minimum 10 transactions

**Message Template:**
- Weekend higher: "You spend {percent}% more on {category} on weekends (${weekend_avg} vs ${weekday_avg} per day)"
- Weekday higher: "You spend {percent}% more on {category} on weekdays (${weekday_avg} vs ${weekend_avg} per day)"

### 3.3 Analytics Engine

#### InsightGenerator Service

**Purpose:** Coordinate insight generation across all types

**Interface:**
```ruby
generator = InsightGenerator.new(
  family: Current.family,
  period: Period.current_month,
  insight_types: [:comparison, :anomaly, :trend, :pattern]
)

insights = generator.generate  # Returns array of Insight objects
```

**Responsibilities:**
- Coordinate calls to type-specific generators
- Apply filtering and sorting logic
- Limit total insights to prevent overwhelming UI
- Cache results for session duration

#### Type-Specific Generators

Each insight type has its own generator class:
- `ComparisonInsightGenerator`
- `AnomalyInsightGenerator`
- `TrendInsightGenerator`
- `PatternInsightGenerator`

**Shared Interface:**
```ruby
class BaseInsightGenerator
  def initialize(family:, period:, options: {})
    @family = family
    @period = period
    @options = options
  end

  def generate
    # Returns array of Insight objects
  end

  private

  def threshold
    @options[:threshold] || 20.0  # Default 20%
  end

  def significant_change?(percent)
    percent.abs >= threshold
  end
end
```

### 3.4 Calculation Algorithms

#### Comparison Calculation

```ruby
# Current period
current_totals = family.income_statement.expense_totals(period: current_period)

# Previous period (same duration)
previous_period = Period.custom(
  start_date: current_period.date_range.first - current_period.duration,
  end_date: current_period.date_range.first - 1.day
)
previous_totals = family.income_statement.expense_totals(period: previous_period)

# Build comparisons
current_totals.category_totals.map do |current_cat|
  previous_cat = previous_totals.category_totals.find { |c| c.category.id == current_cat.category.id }

  next if previous_cat.nil? || previous_cat.total.zero?

  change_percent = ((current_cat.total - previous_cat.total) / previous_cat.total * 100).round(1)

  next unless significant_change?(change_percent)

  Insight.new(
    type: :comparison,
    category: current_cat.category,
    current_value: Money.new(current_cat.total, family.currency),
    comparison_value: Money.new(previous_cat.total, family.currency),
    change_percent: change_percent,
    direction: change_percent.positive? ? :up : :down,
    sentiment: change_percent.positive? ? :negative : :positive,
    message: build_comparison_message(...)
  )
end.compact
```

#### Anomaly Detection Calculation

```ruby
# Current period
current_totals = family.income_statement.expense_totals(period: period)

# Get 3-month medians
category_medians = family.income_statement.median_expense(interval: "month")

# Build anomaly insights
current_totals.category_totals.map do |current_cat|
  median_stat = category_medians.find { |s| s.category_id == current_cat.category.id }

  next if median_stat.nil? || median_stat.median.zero?

  variance_percent = ((current_cat.total - median_stat.median) / median_stat.median * 100).round(1)

  next unless significant_change?(variance_percent)

  Insight.new(
    type: :anomaly,
    category: current_cat.category,
    current_value: Money.new(current_cat.total, family.currency),
    comparison_value: Money.new(median_stat.median, family.currency),
    change_percent: variance_percent,
    direction: variance_percent.positive? ? :up : :down,
    sentiment: variance_percent.positive? ? :negative : :positive,
    message: build_anomaly_message(...),
    metadata: { baseline: "3-month median" }
  )
end.compact
```

#### Trend Analysis Calculation

```ruby
# Get last 6 months of data
monthly_data = (0..5).map do |months_ago|
  month_start = period.date_range.first.beginning_of_month - months_ago.months
  month_end = month_start.end_of_month
  month_period = Period.custom(start_date: month_start, end_date: month_end)

  {
    month: month_start,
    totals: family.income_statement.expense_totals(period: month_period)
  }
end.reverse

# For each category, calculate linear regression
categories = monthly_data.last[:totals].category_totals

categories.map do |category_total|
  # Extract spending values for this category across 6 months
  values = monthly_data.map do |month_data|
    cat = month_data[:totals].category_totals.find { |c| c.category.id == category_total.category.id }
    cat&.total || 0
  end

  # Calculate linear regression (slope, R²)
  slope, r_squared = calculate_linear_regression(values)

  # Convert to percentage change
  avg_value = values.sum / values.size
  percent_change_per_month = (slope / avg_value * 100).round(1)
  total_change = (percent_change_per_month * 6).round(1)

  # Filter: significant trend with good fit
  next unless total_change.abs >= 10 && r_squared > 0.5

  Insight.new(
    type: :trend,
    category: category_total.category,
    current_value: Money.new(values.last, family.currency),
    comparison_value: Money.new(values.first, family.currency),
    change_percent: total_change,
    direction: slope.positive? ? :up : :down,
    sentiment: slope.positive? ? :negative : :positive,
    message: build_trend_message(...),
    metadata: {
      months: 6,
      r_squared: r_squared,
      monthly_change_percent: percent_change_per_month
    }
  )
end.compact
```

#### Pattern Detection Calculation

```ruby
# Get all transactions for period
transactions = Transaction
  .joins(:entry)
  .joins(entry: :account)
  .where(accounts: { family_id: family.id })
  .where(entries: { date: period.date_range, excluded: false })
  .where(kind: ["standard", "loan_payment"])
  .where("entries.amount > 0")  # Expenses only
  .includes(:category, entry: :account)

# Group by category and day type
category_patterns = {}

transactions.each do |transaction|
  category_id = transaction.category&.id || "uncategorized"
  day_type = transaction.entry.date.wday.in?([0, 6]) ? :weekend : :weekday

  category_patterns[category_id] ||= {
    category: transaction.category,
    weekday: { total: 0, days: Set.new },
    weekend: { total: 0, days: Set.new }
  }

  category_patterns[category_id][day_type][:total] += transaction.entry.amount.abs
  category_patterns[category_id][day_type][:days] << transaction.entry.date
end

# Calculate averages and patterns
category_patterns.map do |category_id, data|
  weekday_avg = data[:weekday][:total] / [data[:weekday][:days].size, 1].max
  weekend_avg = data[:weekend][:total] / [data[:weekend][:days].size, 1].max

  # Skip if insufficient data
  next if (data[:weekday][:days].size + data[:weekend][:days].size) < 10

  difference_percent = ((weekend_avg - weekday_avg) / [weekday_avg, 1].max * 100).round(1)

  next unless significant_change?(difference_percent)

  Insight.new(
    type: :pattern,
    category: data[:category],
    current_value: Money.new(weekend_avg, family.currency),
    comparison_value: Money.new(weekday_avg, family.currency),
    change_percent: difference_percent,
    direction: difference_percent.positive? ? :up : :down,
    sentiment: :neutral,  # Patterns are informational, not good/bad
    message: build_pattern_message(...),
    metadata: {
      pattern_type: "weekday_vs_weekend",
      weekday_days: data[:weekday][:days].size,
      weekend_days: data[:weekend][:days].size
    }
  )
end.compact
```

### 3.5 UI Components

#### Insights Section (Reports Dashboard)

**Layout:** Collapsible section with card grid

**Structure:**
```erb
<div class="insights-section">
  <h2>Spending Insights</h2>

  <div class="insight-cards-grid">
    <%= render partial: "insights/card", collection: @insights, as: :insight %>
  </div>

  <% if @insights.empty? %>
    <%= render "insights/empty_state" %>
  <% end %>
</div>
```

#### Insight Card Component

**Purpose:** Display individual insight with appropriate styling

**Props:**
- `insight` (Insight object)
- `clickable` (boolean, default: true)

**Visual Elements:**
- Icon based on insight type (comparison, anomaly, trend, pattern)
- Color coding based on sentiment (green/red/gray)
- Directional arrow (up/down)
- Percentage badge
- Message text
- Optional "View Details" link to category transactions

**Example Structure:**
```erb
<div class="insight-card <%= sentiment_class(insight) %>">
  <div class="insight-icon">
    <%= icon(insight_icon_name(insight)) %>
  </div>

  <div class="insight-content">
    <p class="insight-message"><%= insight.message %></p>

    <div class="insight-details">
      <span class="insight-badge <%= direction_class(insight) %>">
        <%= icon("arrow-#{insight.direction}") %>
        <%= number_to_percentage(insight.change_percent, precision: 1) %>
      </span>

      <span class="insight-amounts">
        <%= insight.current_value.format %> vs <%= insight.comparison_value.format %>
      </span>
    </div>
  </div>

  <% if clickable %>
    <%= link_to "View details", category_transactions_path(insight.category, period: @period), class: "insight-link" %>
  <% end %>
</div>
```

#### Category Trend Chart Component

**Purpose:** Visualize category spending over time with anomaly markers

**Data Structure:**
```javascript
{
  category: {
    id: 123,
    name: "Dining",
    color: "#f97316"
  },
  series: [
    { date: "2024-01-01", amount: 350.00, is_anomaly: false },
    { date: "2024-02-01", amount: 420.00, is_anomaly: true },
    { date: "2024-03-01", amount: 375.00, is_anomaly: false },
    // ...
  ],
  median: 365.00,
  current_period: { date: "2024-03-01", amount: 375.00 }
}
```

**Features:**
- Line chart with category color
- Dashed horizontal line for median
- Markers for anomaly points (different color/size)
- Tooltip showing exact amount and variance from median
- Highlight current period

---

## 4. Implementation Plan

### 4.1 Phase 1: Prerequisites & Data Foundation

**Justification:** Validates existing infrastructure before building new features. Ensures understanding of data availability and calculation patterns.

**Tasks:**

- [ ] Review existing analytics infrastructure
  - Read `app/models/income_statement.rb` to understand `expense_totals()` and `income_totals()` methods
  - Read `app/models/income_statement/category_stats.rb` to understand median/average calculations
  - Read `app/models/income_statement/totals.rb` to understand aggregation SQL patterns
  - Read `app/models/trend.rb` to understand comparison calculations
  - Read `app/models/period.rb` to understand period handling

- [ ] Verify data availability for insights
  - Check test fixtures have sufficient transaction data (at least 3-4 months)
  - Verify categories have transaction history in fixtures
  - Confirm `Category` model has proper associations and scopes
  - Test `IncomeStatement#expense_totals` with fixtures to ensure it returns category breakdown

- [ ] Document calculation patterns in tests
  - Write exploratory test in `test/models/income_statement_test.rb` to verify:
    - `expense_totals()` returns `CategoryTotal` objects
    - Category totals include all non-excluded, non-transfer transactions
    - Period filtering works correctly
  - Write test for `CategoryStats#median_expense` to verify 3-month median calculation
  - Document expected data structures in comments for reference

- [ ] Verify caching strategy
  - Review `family.entries_cache_version` usage in `IncomeStatement`
  - Understand when cache is invalidated (on transaction create/update)
  - Plan session-level caching for generated insights (no database storage initially)

### 4.2 Phase 2: Core Insight Infrastructure

**Justification:** Implements spec sections 3.1 (Data Model), 3.3 (Analytics Engine). Foundation for all insight types.

**Tasks:**

- [ ] Create `Insight` value object in `app/models/insight.rb`
  ```ruby
  # frozen_string_literal: true

  # Value object representing a spending insight
  #
  # Insights are calculated on-demand and not persisted to the database.
  # They provide actionable information about spending patterns.
  #
  # @example Creating a comparison insight
  #   Insight.new(
  #     type: :comparison,
  #     category: dining_category,
  #     message: "You spent 20% more on Dining this month",
  #     current_value: Money.new(45000, "USD"),
  #     comparison_value: Money.new(37500, "USD"),
  #     change_percent: 20.0,
  #     direction: :up,
  #     sentiment: :negative,
  #     metadata: { current_period: "January 2024" }
  #   )
  #
  Insight = Data.define(
    :type,              # Symbol - :comparison, :anomaly, :trend, :pattern
    :category,          # Category object (can be nil for family-wide insights)
    :message,           # String - Human-readable insight text
    :current_value,     # Money - Current period value
    :comparison_value,  # Money - Comparison baseline (previous/median/etc)
    :change_percent,    # Float - Percentage change
    :direction,         # Symbol - :up, :down, :stable
    :sentiment,         # Symbol - :positive, :negative, :neutral
    :metadata           # Hash - Additional context (period names, thresholds, etc)
  ) do
    # Check if insight represents increased spending
    #
    # @return [Boolean]
    def increase?
      direction == :up
    end

    # Check if insight represents decreased spending
    #
    # @return [Boolean]
    def decrease?
      direction == :down
    end

    # Check if change is significant based on absolute percentage
    #
    # @param threshold [Float] Minimum percentage for significance (default: 20.0)
    # @return [Boolean]
    def significant?(threshold: 20.0)
      change_percent.abs >= threshold
    end

    # Get icon name for insight type
    #
    # @return [String] Lucide icon name
    def icon_name
      case type
      when :comparison
        "arrows-left-right"
      when :anomaly
        "alert-triangle"
      when :trend
        direction == :up ? "trending-up" : "trending-down"
      when :pattern
        "calendar"
      else
        "info"
      end
    end

    # Get CSS class for sentiment color coding
    #
    # @return [String] Tailwind class name
    def sentiment_class
      case sentiment
      when :positive
        "text-success"
      when :negative
        "text-destructive"
      else
        "text-tertiary"
      end
    end
  end
  ```

- [ ] Create base generator in `app/models/insight/base_generator.rb`
  ```ruby
  # frozen_string_literal: true

  module Insight
    # Base class for all insight generators
    #
    # Provides common functionality for generating spending insights:
    # - Threshold configuration
    # - Message formatting
    # - Sentiment determination
    # - Filtering logic
    #
    # Subclasses must implement:
    # - `generate` method returning array of Insight objects
    #
    # @abstract Subclass and implement {#generate}
    #
    class BaseGenerator
      attr_reader :family, :period, :options

      # Initialize a new insight generator
      #
      # @param family [Family] The family to generate insights for
      # @param period [Period] The time period to analyze
      # @param options [Hash] Configuration options
      # @option options [Float] :threshold Percentage threshold for significance (default: 20.0)
      # @option options [Integer] :limit Maximum number of insights to return (default: 5)
      def initialize(family:, period:, options: {})
        @family = family
        @period = period
        @options = default_options.merge(options)
      end

      # Generate insights (must be implemented by subclasses)
      #
      # @return [Array<Insight>] Array of generated insights
      # @raise [NotImplementedError] if not implemented by subclass
      def generate
        raise NotImplementedError, "#{self.class} must implement #generate"
      end

      private

      def default_options
        {
          threshold: 20.0,
          limit: 5
        }
      end

      # Get configured threshold percentage
      #
      # @return [Float] Threshold percentage (e.g., 20.0 for 20%)
      def threshold
        options[:threshold]
      end

      # Get configured limit for number of insights
      #
      # @return [Integer] Maximum insights to return
      def limit
        options[:limit]
      end

      # Check if percentage change is significant
      #
      # @param percent [Float] Percentage change
      # @return [Boolean] True if absolute value >= threshold
      def significant_change?(percent)
        percent.abs >= threshold
      end

      # Calculate percentage change between two values
      #
      # @param current [Numeric] Current value
      # @param previous [Numeric] Previous value
      # @return [Float] Percentage change (rounded to 1 decimal)
      def calculate_percent_change(current, previous)
        return 0.0 if previous.zero?
        ((current - previous) / previous * 100).round(1)
      end

      # Determine direction based on change
      #
      # @param change_percent [Float] Percentage change
      # @return [Symbol] :up, :down, or :stable
      def determine_direction(change_percent)
        if change_percent.abs < 1.0
          :stable
        elsif change_percent.positive?
          :up
        else
          :down
        end
      end

      # Determine sentiment for expense changes
      #
      # For expenses: decrease = positive, increase = negative
      # For income: increase = positive, decrease = negative
      #
      # @param direction [Symbol] :up, :down, or :stable
      # @param is_expense [Boolean] True if analyzing expenses (default: true)
      # @return [Symbol] :positive, :negative, or :neutral
      def determine_sentiment(direction, is_expense: true)
        return :neutral if direction == :stable

        if is_expense
          direction == :down ? :positive : :negative
        else
          direction == :up ? :positive : :negative
        end
      end

      # Get income statement for family
      #
      # @return [IncomeStatement] Cached income statement instance
      def income_statement
        @income_statement ||= family.income_statement
      end

      # Get expense totals for a period
      #
      # @param period [Period] Time period to analyze
      # @return [PeriodTotal] Total with category breakdown
      def expense_totals_for(period)
        income_statement.expense_totals(period: period)
      end

      # Get income totals for a period
      #
      # @param period [Period] Time period to analyze
      # @return [PeriodTotal] Total with category breakdown
      def income_totals_for(period)
        income_statement.income_totals(period: period)
      end
    end
  end
  ```

- [ ] Create main coordinator in `app/models/insight/generator.rb`
  ```ruby
  # frozen_string_literal: true

  module Insight
    # Main coordinator for generating all spending insights
    #
    # Orchestrates multiple insight generators and returns a prioritized
    # list of insights for display.
    #
    # @example Generate all insights for current month
    #   generator = Insight::Generator.new(
    #     family: Current.family,
    #     period: Period.current_month
    #   )
    #   insights = generator.generate
    #
    # @example Generate specific insight types
    #   generator = Insight::Generator.new(
    #     family: Current.family,
    #     period: Period.current_month,
    #     insight_types: [:comparison, :anomaly]
    #   )
    #   insights = generator.generate
    #
    class Generator
      attr_reader :family, :period, :insight_types, :options

      # Initialize the insight generator
      #
      # @param family [Family] The family to generate insights for
      # @param period [Period] The time period to analyze
      # @param insight_types [Array<Symbol>] Types to generate (default: all)
      # @param options [Hash] Configuration options passed to generators
      def initialize(family:, period:, insight_types: [:comparison, :anomaly, :trend, :pattern], options: {})
        @family = family
        @period = period
        @insight_types = insight_types
        @options = options
      end

      # Generate all requested insights
      #
      # @return [Array<Insight>] Prioritized array of insights
      def generate
        all_insights = []

        # Generate each insight type
        all_insights += generate_comparison_insights if insight_types.include?(:comparison)
        all_insights += generate_anomaly_insights if insight_types.include?(:anomaly)
        all_insights += generate_trend_insights if insight_types.include?(:trend)
        all_insights += generate_pattern_insights if insight_types.include?(:pattern)

        # Prioritize and limit
        prioritize_insights(all_insights)
      end

      private

      # Generate comparison insights
      def generate_comparison_insights
        ComparisonGenerator.new(
          family: family,
          period: period,
          options: options
        ).generate
      rescue => e
        Rails.logger.error("Failed to generate comparison insights: #{e.message}")
        []
      end

      # Generate anomaly insights
      def generate_anomaly_insights
        AnomalyGenerator.new(
          family: family,
          period: period,
          options: options
        ).generate
      rescue => e
        Rails.logger.error("Failed to generate anomaly insights: #{e.message}")
        []
      end

      # Generate trend insights
      def generate_trend_insights
        TrendGenerator.new(
          family: family,
          period: period,
          options: options
        ).generate
      rescue => e
        Rails.logger.error("Failed to generate trend insights: #{e.message}")
        []
      end

      # Generate pattern insights
      def generate_pattern_insights
        PatternGenerator.new(
          family: family,
          period: period,
          options: options
        ).generate
      rescue => e
        Rails.logger.error("Failed to generate pattern insights: #{e.message}")
        []
      end

      # Prioritize insights for display
      #
      # Priority order:
      # 1. Anomalies (most actionable)
      # 2. Large comparisons (significant changes)
      # 3. Trends (directional information)
      # 4. Patterns (informational)
      #
      # @param insights [Array<Insight>] All generated insights
      # @return [Array<Insight>] Prioritized and limited insights
      def prioritize_insights(insights)
        insights.sort_by do |insight|
          type_priority = case insight.type
          when :anomaly then 1
          when :comparison then 2
          when :trend then 3
          when :pattern then 4
          else 5
          end

          # Secondary sort: larger percentage changes first
          [type_priority, -insight.change_percent.abs]
        end.take(options[:total_limit] || 10)
      end
    end
  end
  ```

- [ ] Write tests for core infrastructure in `test/models/insight/generator_test.rb`
  - Test `Insight` value object creation
  - Test `Insight` helper methods (increase?, significant?, icon_name, etc.)
  - Test `BaseGenerator` initialization and common methods
  - Test `Generator` coordinates multiple insight types
  - Test error handling when individual generators fail
  - Test prioritization logic

### 4.3 Phase 3: Comparison Insights

**Justification:** Implements spec section 3.2 (Insight Types - Comparison). First and most straightforward insight type.

**Tasks:**

- [ ] Create comparison generator in `app/models/insight/comparison_generator.rb`
  ```ruby
  # frozen_string_literal: true

  module Insight
    # Generates month-over-month comparison insights
    #
    # Compares current period spending to previous period of equal duration.
    # Highlights categories with significant changes (≥20% by default).
    #
    # @example Generate comparison insights
    #   generator = Insight::ComparisonGenerator.new(
    #     family: Current.family,
    #     period: Period.current_month
    #   )
    #   insights = generator.generate
    #   # => [
    #   #   Insight(type: :comparison, category: dining, change_percent: 20.0, ...),
    #   #   Insight(type: :comparison, category: groceries, change_percent: -15.5, ...)
    #   # ]
    #
    class ComparisonGenerator < BaseGenerator
      # Generate comparison insights
      #
      # @return [Array<Insight>] Array of comparison insights, sorted by absolute change
      def generate
        current_totals = expense_totals_for(period)
        previous_totals = expense_totals_for(previous_period)

        insights = build_category_comparisons(current_totals, previous_totals)

        # Filter for significant changes and sort by absolute change amount
        insights
          .select { |insight| significant_change?(insight.change_percent) }
          .sort_by { |insight| -insight.current_value.cents.abs }
          .take(limit)
      end

      private

      # Calculate previous period of equal duration
      #
      # @return [Period] Previous period with same duration as current period
      def previous_period
        @previous_period ||= begin
          duration = period.date_range.end - period.date_range.begin
          previous_start = period.date_range.begin - duration - 1.day
          previous_end = period.date_range.begin - 1.day

          Period.custom(start_date: previous_start.to_date, end_date: previous_end.to_date)
        end
      end

      # Build comparison insights for all categories
      #
      # @param current_totals [PeriodTotal] Current period expense totals
      # @param previous_totals [PeriodTotal] Previous period expense totals
      # @return [Array<Insight>] Array of comparison insights
      def build_category_comparisons(current_totals, previous_totals)
        current_totals.category_totals.map do |current_cat|
          previous_cat = previous_totals.category_totals.find { |c| c.category.id == current_cat.category.id }

          # Skip if no previous data or previous was zero (can't calculate percentage)
          next if previous_cat.nil? || previous_cat.total.zero?

          change_percent = calculate_percent_change(current_cat.total, previous_cat.total)
          direction = determine_direction(change_percent)
          sentiment = determine_sentiment(direction, is_expense: true)

          Insight.new(
            type: :comparison,
            category: current_cat.category,
            message: build_message(current_cat, previous_cat, change_percent, direction),
            current_value: Money.new(current_cat.total, family.currency),
            comparison_value: Money.new(previous_cat.total, family.currency),
            change_percent: change_percent,
            direction: direction,
            sentiment: sentiment,
            metadata: {
              current_period: period_label(period),
              comparison_period: period_label(previous_period),
              transaction_count: nil  # Can be added if needed
            }
          )
        end.compact
      end

      # Build human-readable message for comparison insight
      #
      # @param current_cat [CategoryTotal] Current period category total
      # @param previous_cat [CategoryTotal] Previous period category total
      # @param change_percent [Float] Percentage change
      # @param direction [Symbol] :up or :down
      # @return [String] Formatted message
      def build_message(current_cat, previous_cat, change_percent, direction)
        category_name = current_cat.category.name
        current_amount = Money.new(current_cat.total, family.currency).format
        previous_amount = Money.new(previous_cat.total, family.currency).format
        abs_percent = change_percent.abs.round(1)

        if direction == :up
          "You spent #{abs_percent}% more on #{category_name} this period (#{current_amount} vs #{previous_amount})"
        else
          "You spent #{abs_percent}% less on #{category_name} this period (#{current_amount} vs #{previous_amount})"
        end
      end

      # Get human-readable label for period
      #
      # @param period [Period] Period to label
      # @return [String] Period label (e.g., "January 2024", "Last 30 days")
      def period_label(period)
        if period.date_range.begin.beginning_of_month == period.date_range.begin &&
           period.date_range.end.end_of_month == period.date_range.end
          period.date_range.begin.strftime("%B %Y")
        else
          "#{period.date_range.begin.strftime('%b %d')} - #{period.date_range.end.strftime('%b %d, %Y')}"
        end
      end
    end
  end
  ```

- [ ] Write comprehensive tests in `test/models/insight/comparison_generator_test.rb`
  ```ruby
  require "test_helper"

  module Insight
    class ComparisonGeneratorTest < ActiveSupport::TestCase
      setup do
        @family = families(:dylan_family)
        @current_period = Period.current_month
        @generator = ComparisonGenerator.new(
          family: @family,
          period: @current_period
        )
      end

      test "generates comparison insights for categories with significant changes" do
        insights = @generator.generate

        assert insights.is_a?(Array)
        insights.each do |insight|
          assert_equal :comparison, insight.type
          assert insight.category.present?
          assert insight.change_percent.abs >= 20.0  # Default threshold
        end
      end

      test "compares current period to previous period of equal duration" do
        # Create transactions in current and previous months
        current_month_start = Date.current.beginning_of_month
        previous_month_start = current_month_start - 1.month

        # Previous month: $300 on dining
        create_expense_transaction(@family, previous_month_start + 5.days, 30000, category: categories(:dining))

        # Current month: $450 on dining (50% increase)
        create_expense_transaction(@family, current_month_start + 5.days, 45000, category: categories(:dining))

        insights = @generator.generate

        dining_insight = insights.find { |i| i.category.name == "Dining" }
        assert dining_insight.present?, "Should generate dining insight"
        assert_in_delta 50.0, dining_insight.change_percent, 0.1
        assert_equal :up, dining_insight.direction
        assert_equal :negative, dining_insight.sentiment  # Increased expense = negative
      end

      test "calculates percentage change correctly" do
        # Test case: 20% increase
        current = 120
        previous = 100
        change = @generator.send(:calculate_percent_change, current, previous)
        assert_equal 20.0, change

        # Test case: 25% decrease
        current = 75
        previous = 100
        change = @generator.send(:calculate_percent_change, current, previous)
        assert_equal(-25.0, change)
      end

      test "skips categories with no previous data" do
        # Create transaction only in current month (new category)
        create_expense_transaction(@family, Date.current, 10000, category: categories(:dining))

        insights = @generator.generate

        # Should not include dining since no previous period data
        dining_insights = insights.select { |i| i.category.name == "Dining" }
        assert_empty dining_insights
      end

      test "skips categories where previous spending was zero" do
        # Setup data where previous = 0, current = 100
        # (Cannot calculate meaningful percentage change from zero)

        # This should be skipped in results
        insights = @generator.generate

        # Verify no division by zero errors
        assert insights.is_a?(Array)
      end

      test "returns limited number of insights" do
        generator = ComparisonGenerator.new(
          family: @family,
          period: @current_period,
          options: { limit: 3 }
        )

        insights = generator.generate

        assert insights.size <= 3, "Should respect limit option"
      end

      test "sorts insights by absolute change amount" do
        insights = @generator.generate

        # Verify descending order by absolute dollar change
        amounts = insights.map { |i| i.current_value.cents.abs }
        assert_equal amounts, amounts.sort.reverse
      end

      test "builds correct message for increased spending" do
        current_cat = OpenStruct.new(
          category: categories(:dining),
          total: 45000  # $450
        )
        previous_cat = OpenStruct.new(total: 30000)  # $300

        message = @generator.send(:build_message, current_cat, previous_cat, 50.0, :up)

        assert_includes message, "50.0% more"
        assert_includes message, "Dining"
        assert_includes message, "$450"
        assert_includes message, "$300"
      end

      test "builds correct message for decreased spending" do
        current_cat = OpenStruct.new(
          category: categories(:groceries),
          total: 20000  # $200
        )
        previous_cat = OpenStruct.new(total: 30000)  # $300

        message = @generator.send(:build_message, current_cat, previous_cat, -33.3, :down)

        assert_includes message, "33.3% less"
        assert_includes message, "Groceries"
      end

      private

      def create_expense_transaction(family, date, amount_cents, category:)
        account = family.accounts.expense.first || create_account(family)

        Transaction.create!(
          account: account,
          amount: Money.new(amount_cents, family.currency),
          date: date,
          category: category,
          name: "Test transaction",
          kind: :standard
        )
      end
    end
  end
  ```

- [ ] Add integration to main generator
  - Verify `Insight::Generator` calls `ComparisonGenerator` when `:comparison` type requested
  - Test error handling if comparison generation fails

### 4.4 Phase 4: Anomaly Detection

**Justification:** Implements spec section 3.2 (Insight Types - Anomaly). Detects unusual spending vs historical baseline.

**Tasks:**

- [ ] Create anomaly generator in `app/models/insight/anomaly_generator.rb`
  ```ruby
  # frozen_string_literal: true

  module Insight
    # Generates anomaly detection insights
    #
    # Compares current period spending to 3-month median baseline.
    # Identifies unusual spending patterns (≥20% deviation by default).
    #
    # @example Generate anomaly insights
    #   generator = Insight::AnomalyGenerator.new(
    #     family: Current.family,
    #     period: Period.current_month
    #   )
    #   insights = generator.generate
    #   # => [
    #   #   Insight(type: :anomaly, category: dining, change_percent: 35.0, ...),
    #   #   Insight(type: :anomaly, category: utilities, change_percent: -22.0, ...)
    #   # ]
    #
    class AnomalyGenerator < BaseGenerator
      # Number of months to use for median baseline calculation
      BASELINE_MONTHS = 3

      # Generate anomaly insights
      #
      # @return [Array<Insight>] Array of anomaly insights, sorted by variance
      def generate
        current_totals = expense_totals_for(period)
        category_medians = fetch_category_medians

        insights = build_anomaly_insights(current_totals, category_medians)

        # Filter for significant variances and sort by absolute variance
        insights
          .select { |insight| significant_change?(insight.change_percent) }
          .sort_by { |insight| -insight.change_percent.abs }
          .take(limit)
      end

      private

      # Fetch 3-month median spending per category
      #
      # Uses CategoryStats from IncomeStatement
      #
      # @return [Array<CategoryStat>] Array of category statistics with median values
      def fetch_category_medians
        # Use cached category stats for monthly median calculation
        income_statement.median_expense(interval: "month")
      rescue => e
        Rails.logger.error("Failed to fetch category medians: #{e.message}")
        []
      end

      # Build anomaly insights by comparing current to median
      #
      # @param current_totals [PeriodTotal] Current period expense totals
      # @param category_medians [Array<CategoryStat>] Historical median statistics
      # @return [Array<Insight>] Array of anomaly insights
      def build_anomaly_insights(current_totals, category_medians)
        current_totals.category_totals.map do |current_cat|
          median_stat = category_medians.find { |stat| stat.category_id == current_cat.category.id }

          # Skip if no median data or median is zero
          next if median_stat.nil? || median_stat.median.nil? || median_stat.median.zero?

          variance_percent = calculate_percent_change(current_cat.total, median_stat.median)
          direction = determine_direction(variance_percent)
          sentiment = determine_sentiment(direction, is_expense: true)

          Insight.new(
            type: :anomaly,
            category: current_cat.category,
            message: build_message(current_cat, median_stat, variance_percent, direction),
            current_value: Money.new(current_cat.total, family.currency),
            comparison_value: Money.new(median_stat.median, family.currency),
            change_percent: variance_percent,
            direction: direction,
            sentiment: sentiment,
            metadata: {
              baseline: "#{BASELINE_MONTHS}-month median",
              baseline_months: BASELINE_MONTHS,
              median_value: median_stat.median,
              current_period: period_label(period)
            }
          )
        end.compact
      end

      # Build human-readable message for anomaly insight
      #
      # @param current_cat [CategoryTotal] Current period category total
      # @param median_stat [CategoryStat] Historical median statistic
      # @param variance_percent [Float] Percentage variance from median
      # @param direction [Symbol] :up or :down
      # @return [String] Formatted message
      def build_message(current_cat, median_stat, variance_percent, direction)
        category_name = current_cat.category.name
        current_amount = Money.new(current_cat.total, family.currency).format
        median_amount = Money.new(median_stat.median, family.currency).format
        abs_percent = variance_percent.abs.round(1)

        if direction == :up
          "Your #{category_name} spending is #{abs_percent}% higher than usual (#{current_amount} vs #{median_amount} median)"
        else
          "Your #{category_name} spending is #{abs_percent}% lower than usual (#{current_amount} vs #{median_amount} median)"
        end
      end

      # Get human-readable label for period
      #
      # @param period [Period] Period to label
      # @return [String] Period label
      def period_label(period)
        if period.date_range.begin.beginning_of_month == period.date_range.begin &&
           period.date_range.end.end_of_month == period.date_range.end
          period.date_range.begin.strftime("%B %Y")
        else
          "current period"
        end
      end
    end
  end
  ```

- [ ] Write comprehensive tests in `test/models/insight/anomaly_generator_test.rb`
  - Test anomaly detection against 3-month median
  - Test with insufficient historical data (< 3 months)
  - Test high variance detection (≥20% above median)
  - Test low variance detection (≥20% below median)
  - Test message generation for both directions
  - Test sorting by absolute variance
  - Test limit option
  - Mock `CategoryStats` if needed for consistent test data

- [ ] Add integration to main generator
  - Verify `Insight::Generator` calls `AnomalyGenerator` when `:anomaly` type requested
  - Test error handling

### 4.5 Phase 5: Trend Analysis

**Justification:** Implements spec section 3.2 (Insight Types - Trend). Multi-month trend detection.

**Tasks:**

- [ ] Create trend generator in `app/models/insight/trend_generator.rb`
  ```ruby
  # frozen_string_literal: true

  module Insight
    # Generates trend analysis insights
    #
    # Analyzes spending trends over the last 6 months using linear regression.
    # Identifies categories with consistent upward or downward trends.
    #
    # @example Generate trend insights
    #   generator = Insight::TrendGenerator.new(
    #     family: Current.family,
    #     period: Period.current_month
    #   )
    #   insights = generator.generate
    #   # => [
    #   #   Insight(type: :trend, category: subscriptions, change_percent: 15.0, ...),
    #   #   Insight(type: :trend, category: transportation, change_percent: -12.0, ...)
    #   # ]
    #
    class TrendGenerator < BaseGenerator
      # Number of months to analyze for trends
      TREND_MONTHS = 6

      # Minimum R² value for trend to be considered consistent
      MIN_R_SQUARED = 0.5

      # Minimum total percentage change over trend period to be significant
      MIN_TOTAL_CHANGE = 10.0

      # Generate trend insights
      #
      # @return [Array<Insight>] Array of trend insights, sorted by trend strength
      def generate
        monthly_data = fetch_monthly_data
        insights = build_trend_insights(monthly_data)

        # Filter for significant trends and sort by strength (R²)
        insights
          .select { |insight| significant_trend?(insight) }
          .sort_by { |insight| -insight.metadata[:r_squared] }
          .take(limit)
      end

      private

      # Fetch expense totals for each of the last N months
      #
      # @return [Array<Hash>] Array of monthly data with totals
      def fetch_monthly_data
        (0...TREND_MONTHS).map do |months_ago|
          month_start = period.date_range.first.beginning_of_month - months_ago.months
          month_end = month_start.end_of_month
          month_period = Period.custom(start_date: month_start, end_date: month_end)

          {
            month: month_start,
            period: month_period,
            totals: expense_totals_for(month_period)
          }
        end.reverse  # Oldest to newest
      end

      # Build trend insights for all categories
      #
      # @param monthly_data [Array<Hash>] Monthly expense data
      # @return [Array<Insight>] Array of trend insights
      def build_trend_insights(monthly_data)
        # Get unique categories from the most recent month
        categories = monthly_data.last[:totals].category_totals

        categories.map do |category_total|
          # Extract spending values for this category across all months
          values = monthly_data.map do |month_data|
            cat = month_data[:totals].category_totals.find { |c| c.category.id == category_total.category.id }
            cat&.total || 0
          end

          # Calculate linear regression
          slope, r_squared = calculate_linear_regression(values)

          # Skip if insufficient data or poor fit
          next if values.all?(&:zero?) || r_squared < MIN_R_SQUARED

          # Convert slope to percentage change
          avg_value = values.sum / values.size.to_f
          next if avg_value.zero?

          percent_change_per_month = (slope / avg_value * 100).round(1)
          total_change = (percent_change_per_month * TREND_MONTHS).round(1)

          # Skip if change is too small to be meaningful
          next if total_change.abs < MIN_TOTAL_CHANGE

          direction = determine_direction(total_change)
          sentiment = determine_sentiment(direction, is_expense: true)

          Insight.new(
            type: :trend,
            category: category_total.category,
            message: build_message(category_total.category, total_change, direction),
            current_value: Money.new(values.last, family.currency),
            comparison_value: Money.new(values.first, family.currency),
            change_percent: total_change,
            direction: direction,
            sentiment: sentiment,
            metadata: {
              months: TREND_MONTHS,
              r_squared: r_squared,
              monthly_change_percent: percent_change_per_month,
              values: values
            }
          )
        end.compact
      end

      # Calculate linear regression slope and R² value
      #
      # Uses simple linear regression: y = mx + b
      # where x = month index (0, 1, 2, ...) and y = spending amount
      #
      # @param values [Array<Numeric>] Array of monthly spending values
      # @return [Array(Float, Float)] [slope, r_squared]
      def calculate_linear_regression(values)
        n = values.size
        x_values = (0...n).to_a

        # Calculate means
        x_mean = x_values.sum / n.to_f
        y_mean = values.sum / n.to_f

        # Calculate slope (m)
        numerator = x_values.zip(values).sum { |x, y| (x - x_mean) * (y - y_mean) }
        denominator = x_values.sum { |x| (x - x_mean)**2 }

        slope = denominator.zero? ? 0 : numerator / denominator

        # Calculate R² (coefficient of determination)
        ss_tot = values.sum { |y| (y - y_mean)**2 }
        ss_res = x_values.zip(values).sum { |x, y| (y - (slope * x + (y_mean - slope * x_mean)))**2 }

        r_squared = ss_tot.zero? ? 0 : 1 - (ss_res / ss_tot)

        [slope, r_squared]
      end

      # Check if trend is significant
      #
      # @param insight [Insight] Trend insight to check
      # @return [Boolean] True if trend meets significance criteria
      def significant_trend?(insight)
        insight.change_percent.abs >= MIN_TOTAL_CHANGE &&
          insight.metadata[:r_squared] >= MIN_R_SQUARED
      end

      # Build human-readable message for trend insight
      #
      # @param category [Category] Category with trend
      # @param total_change [Float] Total percentage change over period
      # @param direction [Symbol] :up or :down
      # @return [String] Formatted message
      def build_message(category, total_change, direction)
        category_name = category.name
        abs_percent = total_change.abs.round(1)

        if direction == :up
          "Your #{category_name} spending has increased #{abs_percent}% over the last #{TREND_MONTHS} months"
        else
          "Your #{category_name} spending has decreased #{abs_percent}% over the last #{TREND_MONTHS} months"
        end
      end
    end
  end
  ```

- [ ] Write comprehensive tests in `test/models/insight/trend_generator_test.rb`
  - Test linear regression calculation accuracy
  - Test R² calculation
  - Test trend detection with increasing values
  - Test trend detection with decreasing values
  - Test filtering of weak trends (R² < 0.5)
  - Test filtering of small changes (< 10% total)
  - Test with flat/stable spending (no trend)
  - Test message generation

- [ ] Add integration to main generator
  - Verify `Insight::Generator` calls `TrendGenerator` when `:trend` type requested
  - Test error handling

### 4.6 Phase 6: Pattern Detection

**Justification:** Implements spec section 3.2 (Insight Types - Pattern). Weekday vs weekend spending analysis.

**Tasks:**

- [ ] Create pattern generator in `app/models/insight/pattern_generator.rb`
  ```ruby
  # frozen_string_literal: true

  module Insight
    # Generates spending pattern insights
    #
    # Analyzes weekday vs weekend spending patterns per category.
    # Identifies categories where spending differs significantly by day type.
    #
    # @example Generate pattern insights
    #   generator = Insight::PatternGenerator.new(
    #     family: Current.family,
    #     period: Period.current_month
    #   )
    #   insights = generator.generate
    #   # => [
    #   #   Insight(type: :pattern, category: dining, change_percent: 30.0, ...),
    #   #   Insight(type: :pattern, category: entertainment, change_percent: 45.0, ...)
    #   # ]
    #
    class PatternGenerator < BaseGenerator
      # Minimum number of transactions required to detect patterns
      MIN_TRANSACTIONS = 10

      # Generate pattern insights
      #
      # @return [Array<Insight>] Array of pattern insights, sorted by difference
      def generate
        transactions = fetch_transactions
        patterns = analyze_weekday_weekend_patterns(transactions)

        # Filter for significant patterns and sort by difference
        patterns
          .select { |insight| significant_change?(insight.change_percent) }
          .sort_by { |insight| -insight.change_percent.abs }
          .take(limit)
      end

      private

      # Fetch all expense transactions for the period
      #
      # @return [ActiveRecord::Relation] Transactions for analysis
      def fetch_transactions
        Transaction
          .joins(:entry)
          .joins(entry: :account)
          .where(accounts: { family_id: family.id, status: ["draft", "active"] })
          .where(entries: { date: period.date_range, excluded: false })
          .where(kind: ["standard", "loan_payment"])
          .where("entries.amount > 0")  # Expenses only (positive amounts)
          .includes(:category, entry: :account)
      end

      # Analyze weekday vs weekend patterns for each category
      #
      # @param transactions [ActiveRecord::Relation] Transactions to analyze
      # @return [Array<Insight>] Array of pattern insights
      def analyze_weekday_weekend_patterns(transactions)
        # Group transactions by category and day type
        category_patterns = {}

        transactions.each do |transaction|
          category = transaction.category || default_category
          category_id = category.id
          day_type = weekend_day?(transaction.entry.date) ? :weekend : :weekday

          category_patterns[category_id] ||= {
            category: category,
            weekday: { total: 0, days: Set.new, transactions: 0 },
            weekend: { total: 0, days: Set.new, transactions: 0 }
          }

          amount = transaction.entry.amount.abs
          category_patterns[category_id][day_type][:total] += amount
          category_patterns[category_id][day_type][:days] << transaction.entry.date
          category_patterns[category_id][day_type][:transactions] += 1
        end

        # Calculate patterns for each category
        category_patterns.map do |category_id, data|
          build_pattern_insight(data)
        end.compact
      end

      # Build pattern insight for a category
      #
      # @param data [Hash] Category pattern data
      # @return [Insight, nil] Pattern insight or nil if insufficient data
      def build_pattern_insight(data)
        total_transactions = data[:weekday][:transactions] + data[:weekend][:transactions]

        # Skip if insufficient transactions
        return nil if total_transactions < MIN_TRANSACTIONS

        # Calculate average daily spending
        weekday_days = data[:weekday][:days].size
        weekend_days = data[:weekend][:days].size

        # Skip if no data for either day type
        return nil if weekday_days.zero? || weekend_days.zero?

        weekday_avg = data[:weekday][:total] / weekday_days.to_f
        weekend_avg = data[:weekend][:total] / weekend_days.to_f

        # Calculate percentage difference
        # Use weekday as baseline (positive = spend more on weekends)
        difference_percent = ((weekend_avg - weekday_avg) / weekday_avg * 100).round(1)

        direction = determine_direction(difference_percent)

        Insight.new(
          type: :pattern,
          category: data[:category],
          message: build_message(data[:category], difference_percent, weekday_avg, weekend_avg),
          current_value: Money.new(weekend_avg, family.currency),
          comparison_value: Money.new(weekday_avg, family.currency),
          change_percent: difference_percent,
          direction: direction,
          sentiment: :neutral,  # Patterns are informational, not good/bad
          metadata: {
            pattern_type: "weekday_vs_weekend",
            weekday_days: weekday_days,
            weekend_days: weekend_days,
            weekday_total: data[:weekday][:total],
            weekend_total: data[:weekend][:total],
            total_transactions: total_transactions
          }
        )
      end

      # Check if date falls on weekend
      #
      # @param date [Date] Date to check
      # @return [Boolean] True if Saturday or Sunday
      def weekend_day?(date)
        date.wday.in?([0, 6])  # 0 = Sunday, 6 = Saturday
      end

      # Build human-readable message for pattern insight
      #
      # @param category [Category] Category with pattern
      # @param difference_percent [Float] Percentage difference
      # @param weekday_avg [Float] Average weekday spending
      # @param weekend_avg [Float] Average weekend spending
      # @return [String] Formatted message
      def build_message(category, difference_percent, weekday_avg, weekend_avg)
        category_name = category.name
        abs_percent = difference_percent.abs.round(1)

        weekday_amount = Money.new(weekday_avg, family.currency).format
        weekend_amount = Money.new(weekend_avg, family.currency).format

        if difference_percent.positive?
          "You spend #{abs_percent}% more on #{category_name} on weekends (#{weekend_amount} vs #{weekday_amount} per day)"
        else
          "You spend #{abs_percent}% more on #{category_name} on weekdays (#{weekday_amount} vs #{weekend_amount} per day)"
        end
      end

      # Get default uncategorized category
      #
      # @return [Category] Uncategorized category
      def default_category
        @default_category ||= family.categories.find_by(name: "Uncategorized")
      end
    end
  end
  ```

- [ ] Write comprehensive tests in `test/models/insight/pattern_generator_test.rb`
  - Test weekday vs weekend detection
  - Test with insufficient transactions (< 10)
  - Test with only weekday transactions
  - Test with only weekend transactions
  - Test percentage calculation (weekend higher and weekday higher)
  - Test message generation for both patterns
  - Test sentiment is always neutral for patterns

- [ ] Add integration to main generator
  - Verify `Insight::Generator` calls `PatternGenerator` when `:pattern` type requested
  - Test error handling

### 4.7 Phase 7: Reports Dashboard Integration

**Justification:** Implements spec sections 3.5 (UI Components). User-facing dashboard integration.

**Tasks:**

- [ ] Add insights action to ReportsController in `app/controllers/reports_controller.rb`
  ```ruby
  # Add to existing ReportsController

  # GET /reports/insights
  def insights
    # Use period from params or default to current month
    @period = set_period  # Uses existing Periodable concern

    # Generate insights on-demand
    @insights = generate_insights

    # Group insights by type for organized display
    @insights_by_type = @insights.group_by(&:type)
  end

  private

  # Generate spending insights for current family and period
  #
  # @return [Array<Insight>] Array of generated insights
  def generate_insights
    Insight::Generator.new(
      family: Current.family,
      period: @period,
      insight_types: [:comparison, :anomaly, :trend, :pattern],
      options: { threshold: 20.0, total_limit: 10 }
    ).generate
  rescue => e
    Rails.logger.error("Failed to generate insights: #{e.message}")
    []
  end
  ```

- [ ] Add route in `config/routes.rb`
  ```ruby
  # Add to existing reports routes
  resources :reports, only: [:index] do
    collection do
      get :insights
      # ... other report routes
    end
  end
  ```

- [ ] Add insights section to reports index in `app/views/reports/index.html.erb`
  - Follow existing `build_reports_sections` pattern from ReportsController
  - Add "Spending Insights" as a collapsible section
  - Use existing section rendering logic
  - Reference pattern from `app/views/pages/dashboard.html.erb` for section structure

- [ ] Create insights partial in `app/views/reports/_insights.html.erb`
  ```erb
  <div class="insights-section">
    <div class="insights-header mb-4">
      <h3 class="text-lg font-semibold text-primary"><%= t(".heading") %></h3>
      <p class="text-sm text-tertiary"><%= t(".description") %></p>
    </div>

    <% if insights.any? %>
      <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
        <%= render partial: "reports/insights/card", collection: insights, as: :insight %>
      </div>
    <% else %>
      <%= render "reports/insights/empty_state" %>
    <% end %>
  </div>
  ```

- [ ] Create insight card component in `app/views/reports/insights/_card.html.erb`
  ```erb
  <%
    # Determine styling based on insight properties
    sentiment_class = case insight.sentiment
    when :positive then "border-success bg-success/5"
    when :negative then "border-destructive bg-destructive/5"
    else "border-primary bg-surface-inset"
    end
  %>

  <div class="insight-card p-4 rounded-lg border <%= sentiment_class %>">
    <div class="flex items-start gap-3">
      <div class="flex-shrink-0 mt-1">
        <%= icon(insight.icon_name, class: "w-5 h-5 #{insight.sentiment_class}") %>
      </div>

      <div class="flex-1 min-w-0">
        <p class="text-sm text-primary mb-2">
          <%= insight.message %>
        </p>

        <div class="flex items-center gap-3 text-xs text-tertiary">
          <span class="inline-flex items-center gap-1 font-mono">
            <%= icon("arrow-#{insight.direction}", class: "w-3 h-3") %>
            <%= number_to_percentage(insight.change_percent.abs, precision: 1) %>
          </span>

          <span>
            <%= insight.current_value.format %> vs <%= insight.comparison_value.format %>
          </span>
        </div>

        <% if insight.metadata[:baseline].present? %>
          <p class="text-xs text-tertiary mt-1">
            <%= t(".compared_to", baseline: insight.metadata[:baseline]) %>
          </p>
        <% end %>
      </div>
    </div>

    <% if insight.category.present? %>
      <div class="mt-3 pt-3 border-t border-primary">
        <%= link_to transactions_path(category_id: insight.category.id, period: @period),
                    class: "text-xs text-primary hover:text-link flex items-center gap-1" do %>
          <%= t(".view_transactions") %>
          <%= icon("chevron-right", class: "w-3 h-3") %>
        <% end %>
      </div>
    <% end %>
  </div>
  ```

- [ ] Create empty state in `app/views/reports/insights/_empty_state.html.erb`
  ```erb
  <div class="empty-state text-center py-12 px-4 bg-surface-inset rounded-lg">
    <%= icon("lightbulb", class: "w-12 h-12 text-tertiary mx-auto mb-4") %>

    <h3 class="text-lg font-semibold text-primary mb-2">
      <%= t(".no_insights_heading") %>
    </h3>

    <p class="text-sm text-tertiary max-w-md mx-auto">
      <%= t(".no_insights_description") %>
    </p>

    <% if @period.date_range.begin > 3.months.ago.to_date %>
      <p class="text-xs text-tertiary mt-4">
        <%= t(".insufficient_data_hint") %>
      </p>
    <% end %>
  </div>
  ```

- [ ] Add localization in `config/locales/views/reports/insights.en.yml`
  ```yaml
  en:
    reports:
      insights:
        heading: "Spending Insights"
        description: "Discover patterns and unusual spending in your transactions"
        compared_to: "Compared to %{baseline}"
        view_transactions: "View transactions"

        card:
          compared_to: "Compared to %{baseline}"
          view_transactions: "View transactions"

        empty_state:
          no_insights_heading: "No insights available yet"
          no_insights_description: "We need at least 2-3 months of transaction data to generate meaningful spending insights."
          insufficient_data_hint: "Keep tracking your expenses and check back next month for personalized insights."
  ```

- [ ] Update reports sections builder in ReportsController
  ```ruby
  # In ReportsController#index, add to sections array:
  {
    key: "spending_insights",
    title: t(".spending_insights.title"),
    partial: "reports/insights",
    locals: { insights: @insights, period: @period },
    visible: @insights.any?,
    collapsible: true,
    order: 1  # Show near top of reports
  }
  ```

- [ ] Add navigation link to insights
  - Add link in reports navigation or dashboard navigation
  - Badge showing count of high-priority insights (optional)
  - Follow existing navigation patterns

### 4.8 Phase 8: Category Trend Visualization

**Justification:** Implements spec section 3.5 (UI Components - Visualization). Enhanced charts for trend insights.

**Tasks:**

- [ ] Create category trend chart component in `app/views/reports/insights/_trend_chart.html.erb`
  ```erb
  <%
    # This partial renders a time-series chart for a specific category
    # showing monthly spending with anomaly markers
  %>

  <div class="category-trend-chart"
       data-controller="category-trend-chart"
       data-category-trend-chart-data-value="<%= chart_data.to_json %>"
       data-category-trend-chart-category-value="<%= category.name %>"
       data-category-trend-chart-color-value="<%= category.color %>">

    <div class="chart-header mb-4">
      <h4 class="text-sm font-semibold text-primary flex items-center gap-2">
        <%= icon(category.lucide_icon, class: "w-4 h-4", style: "color: #{category.color}") %>
        <%= category.name %> <%= t(".spending_trend") %>
      </h4>
    </div>

    <div class="chart-container" style="height: 200px;">
      <!-- Chart rendered by Stimulus controller -->
    </div>

    <div class="chart-legend mt-2 flex items-center gap-4 text-xs text-tertiary">
      <span class="flex items-center gap-1">
        <span class="w-3 h-0.5 bg-current"></span>
        <%= t(".monthly_spending") %>
      </span>
      <span class="flex items-center gap-1">
        <span class="w-3 h-0.5 border-t border-dashed border-current"></span>
        <%= t(".median_baseline") %>
      </span>
      <span class="flex items-center gap-1">
        <%= icon("alert-circle", class: "w-3 h-3 text-destructive") %>
        <%= t(".anomaly") %>
      </span>
    </div>
  </div>
  ```

- [ ] Create Stimulus controller in `app/javascript/controllers/category_trend_chart_controller.js`
  ```javascript
  import { Controller } from "@hotwired/stimulus"
  import * as d3 from "d3"

  export default class extends Controller {
    static values = {
      data: Object,
      category: String,
      color: String
    }

    connect() {
      this.renderChart()
    }

    renderChart() {
      const data = this.dataValue
      const color = this.colorValue || "#3b82f6"

      // Clear existing chart
      this.element.querySelector(".chart-container").innerHTML = ""

      // Setup dimensions
      const margin = { top: 20, right: 20, bottom: 30, left: 50 }
      const width = this.element.querySelector(".chart-container").offsetWidth - margin.left - margin.right
      const height = 200 - margin.top - margin.bottom

      // Create SVG
      const svg = d3.select(this.element.querySelector(".chart-container"))
        .append("svg")
        .attr("width", width + margin.left + margin.right)
        .attr("height", height + margin.top + margin.bottom)
        .append("g")
        .attr("transform", `translate(${margin.left},${margin.top})`)

      // Parse dates
      const parseDate = d3.timeParse("%Y-%m-%d")
      data.series.forEach(d => {
        d.parsedDate = parseDate(d.date)
      })

      // Setup scales
      const x = d3.scaleTime()
        .domain(d3.extent(data.series, d => d.parsedDate))
        .range([0, width])

      const y = d3.scaleLinear()
        .domain([0, d3.max(data.series, d => Math.max(d.amount, data.median || 0)) * 1.1])
        .range([height, 0])

      // Add axes
      svg.append("g")
        .attr("transform", `translate(0,${height})`)
        .call(d3.axisBottom(x).ticks(6))
        .style("color", "var(--color-tertiary)")

      svg.append("g")
        .call(d3.axisLeft(y).ticks(5).tickFormat(d => `$${d}`))
        .style("color", "var(--color-tertiary)")

      // Add median line (dashed)
      if (data.median) {
        svg.append("line")
          .attr("x1", 0)
          .attr("x2", width)
          .attr("y1", y(data.median))
          .attr("y2", y(data.median))
          .style("stroke", "var(--color-tertiary)")
          .style("stroke-dasharray", "4,4")
          .style("opacity", 0.5)
      }

      // Add spending line
      const line = d3.line()
        .x(d => x(d.parsedDate))
        .y(d => y(d.amount))
        .curve(d3.curveMonotoneX)

      svg.append("path")
        .datum(data.series)
        .attr("fill", "none")
        .attr("stroke", color)
        .attr("stroke-width", 2)
        .attr("d", line)

      // Add anomaly markers
      const anomalies = data.series.filter(d => d.is_anomaly)
      svg.selectAll(".anomaly-marker")
        .data(anomalies)
        .enter()
        .append("circle")
        .attr("class", "anomaly-marker")
        .attr("cx", d => x(d.parsedDate))
        .attr("cy", d => y(d.amount))
        .attr("r", 5)
        .style("fill", "var(--color-destructive)")
        .style("stroke", "white")
        .style("stroke-width", 2)

      // Add hover tooltip
      const tooltip = d3.select(this.element)
        .append("div")
        .style("position", "absolute")
        .style("background", "var(--color-container)")
        .style("padding", "8px")
        .style("border-radius", "4px")
        .style("box-shadow", "0 2px 8px rgba(0,0,0,0.1)")
        .style("pointer-events", "none")
        .style("opacity", 0)
        .style("font-size", "12px")

      svg.selectAll(".data-point")
        .data(data.series)
        .enter()
        .append("circle")
        .attr("class", "data-point")
        .attr("cx", d => x(d.parsedDate))
        .attr("cy", d => y(d.amount))
        .attr("r", 4)
        .style("fill", color)
        .style("cursor", "pointer")
        .on("mouseover", (event, d) => {
          tooltip.transition().duration(200).style("opacity", 1)

          const variance = data.median ? ((d.amount - data.median) / data.median * 100).toFixed(1) : null
          const varianceText = variance ? `<br><span style="color: ${variance > 0 ? 'var(--color-destructive)' : 'var(--color-success)'}">
            ${variance > 0 ? '+' : ''}${variance}% vs median
          </span>` : ''

          tooltip.html(`
            <strong>${d3.timeFormat("%b %Y")(d.parsedDate)}</strong><br>
            $${d.amount.toFixed(2)}
            ${varianceText}
          `)
          .style("left", (event.pageX + 10) + "px")
          .style("top", (event.pageY - 10) + "px")
        })
        .on("mouseout", () => {
          tooltip.transition().duration(200).style("opacity", 0)
        })
    }
  }
  ```

- [ ] Build chart data in controller helper method
  ```ruby
  # Add to ReportsController or create InsightsHelper

  # Build category trend chart data
  #
  # @param category [Category] Category to chart
  # @param months [Integer] Number of months to show (default: 6)
  # @return [Hash] Chart data structure
  def build_category_trend_data(category, months: 6)
    # Fetch last N months of data
    series_data = (0...months).map do |months_ago|
      month_start = Date.current.beginning_of_month - months_ago.months
      month_end = month_start.end_of_month
      period = Period.custom(start_date: month_start, end_date: month_end)

      totals = Current.family.income_statement.expense_totals(period: period)
      cat_total = totals.category_totals.find { |c| c.category.id == category.id }

      amount = cat_total&.total || 0

      {
        date: month_start.iso8601,
        amount: amount / 100.0,  # Convert cents to dollars
        is_anomaly: false  # Will be set based on median comparison
      }
    end.reverse

    # Calculate 3-month median
    values = series_data.map { |d| d[:amount] }
    median = calculate_median(values)

    # Mark anomalies (>20% from median)
    series_data.each do |point|
      if median > 0
        variance_percent = ((point[:amount] - median) / median * 100).abs
        point[:is_anomaly] = variance_percent >= 20
      end
    end

    {
      category: {
        id: category.id,
        name: category.name,
        color: category.color
      },
      series: series_data,
      median: median,
      current_period: series_data.last
    }
  end

  # Calculate median of numeric array
  def calculate_median(values)
    return 0 if values.empty?
    sorted = values.sort
    mid = sorted.length / 2
    sorted.length.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
  end
  ```

- [ ] Add chart section to insights view
  - Show trend charts for categories with trend insights
  - Collapsible "View Trends" section
  - Grid layout for multiple category charts

### 4.9 Phase 9: Testing & Documentation

**Justification:** Validation and documentation. Ensures feature works end-to-end.

**Tasks:**

- [ ] Write system test in `test/system/spending_insights_test.rb`
  ```ruby
  require "application_system_test_case"

  class SpendingInsightsTest < ApplicationSystemTestCase
    setup do
      sign_in users(:dylan)
      @family = families(:dylan_family)
      setup_test_data
    end

    test "viewing spending insights on reports page" do
      visit reports_path

      # Insights section should be visible
      assert_selector "h3", text: "Spending Insights"

      # Should show insight cards
      assert_selector ".insight-card", minimum: 1
    end

    test "displays comparison insight for increased spending" do
      visit reports_path

      # Should show insight about dining increase
      within ".insight-card", match: :first do
        assert_text /spent.*more.*Dining/i
        assert_selector "[data-icon='arrow-up']"
      end
    end

    test "displays anomaly insight for unusual spending" do
      # Create unusual spending pattern
      create_anomaly_spending

      visit reports_path

      within ".insights-section" do
        assert_text /higher than usual/i
      end
    end

    test "shows empty state when no insights available" do
      # Clear all transactions
      @family.transactions.destroy_all

      visit reports_path

      within ".insights-section" do
        assert_text "No insights available yet"
        assert_text "at least 2-3 months"
      end
    end

    test "clicking insight card shows related transactions" do
      visit reports_path

      # Click on first insight card
      within ".insight-card", match: :first do
        click_link "View transactions"
      end

      # Should navigate to transactions filtered by category
      assert_current_path transactions_path
      assert_selector ".transaction-row", minimum: 1
    end

    test "period selector updates insights" do
      visit reports_path

      # Change period
      select "Last 30 Days", from: "period"

      # Should reload with new insights
      assert_selector ".insight-card"
    end

    private

    def setup_test_data
      # Create transaction history for last 3 months
      # ... setup code
    end

    def create_anomaly_spending
      # Create spending pattern that triggers anomaly
      # ... setup code
    end
  end
  ```

- [ ] Write integration test in `test/integration/spending_insights_generation_test.rb`
  - Test full workflow from transaction data to insight generation
  - Test caching behavior
  - Test error handling when data is incomplete
  - Test all four insight types generate correctly

- [ ] Write controller tests in `test/controllers/reports_controller_test.rb`
  - Test insights action returns insights
  - Test empty state when no data
  - Test period filtering
  - Test error handling

- [ ] Run full test suite: `bin/rails test`
- [ ] Run system tests: `bin/rails test:system`
- [ ] Run linting: `bin/rubocop -f github -a`
- [ ] Check for N+1 queries using bullet gem or manual inspection

- [ ] Create user documentation
  - Overview of spending insights feature
  - Explanation of each insight type (comparison, anomaly, trend, pattern)
  - How to interpret insights
  - Tips for actionable changes based on insights
  - FAQ section

- [ ] Add inline help in UI
  - Tooltip explaining "3-month median" for anomalies
  - Help icon with insight type descriptions
  - Link to full documentation

- [ ] Performance optimization review
  - Add database indexes if needed (categories, transactions by date)
  - Review query performance for large datasets
  - Consider adding background job option for very large families
  - Document caching strategy

---

## Additional Considerations

### Performance Notes
- Leverage existing `IncomeStatement` caching (uses `entries_cache_version`)
- Session-level caching for generated insights (avoid recalculation on page refresh)
- Consider memoization in generators for repeated calculations
- Monitor query performance with large transaction volumes

### Future Enhancements (Not in Scope)
- Custom insight thresholds per user (some users may want 15% or 25%)
- Email notifications for significant anomalies
- Saving favorite insights or dismissing insights
- Comparative insights across families (anonymized benchmarking)
- Seasonal pattern detection (holiday spending, summer patterns)
- Goal-based insights ("You're on track to save $X this month")
- AI-generated personalized recommendations
- Export insights to PDF/email summary
- Insight history tracking (see how patterns change over time)

### Edge Cases to Handle
- Partial months (prorate comparisons appropriately)
- Multi-currency families (ensure currency conversion)
- New accounts with < 3 months history (skip anomaly detection)
- Categories with sporadic spending (filter by transaction count)
- Zero or negative spending in comparison periods (skip percentage calculation)

### Accessibility
- ARIA labels for insight cards
- Keyboard navigation for chart interactions
- Screen reader friendly insight messages
- Sufficient color contrast for sentiment indicators

---

**End of Implementation Plan**
