# Net Worth Projection - Implementation Plan

## Overview

A future-oriented net worth projection feature that calculates and visualizes projected wealth based on historical growth patterns. Analyzes at least 6 months of transaction history to determine average wealth accumulation rate, then projects future net worth across user-selected timeframes with multiple scenarios (conservative, realistic, optimistic).

**Key Components:**
- Historical growth rate calculator analyzing past wealth accumulation patterns
- Linear projection algorithm generating future net worth estimates
- Three projection scenarios providing range of outcomes
- Enhanced Home page Net Worth card with expandable projections section
- User-selectable timeframes (1yr, 2yr, 3yr, 5yr, 10yr, 20yr)
- Extended D3.js visualization distinguishing historical vs projected data

**Sequencing Logic:**
1. Backend growth rate calculator (requires 6+ months historical data)
2. Backend projection engine with multi-scenario support
3. Service layer integration extending existing NetWorth class
4. Controller enhancement for Home page data delivery
5. Frontend Net Worth card enhancement with projection UI
6. Chart visualization updates for projection display
7. Testing and validation
8. i18n and documentation

---

## Table of Contents
1. [Phase 1: Backend - Historical Growth Rate Calculator](#phase-1)
2. [Phase 2: Backend - Projection Engine](#phase-2)
3. [Phase 3: Backend - Service Integration](#phase-3)
4. [Phase 4: Controller - Home Page Data Endpoint](#phase-4)
5. [Phase 5: Frontend - Enhanced Net Worth Card](#phase-5)
6. [Phase 6: Frontend - Chart Visualization](#phase-6)
7. [Phase 7: Testing](#phase-7)
8. [Phase 8: i18n and Documentation](#phase-8)

---

## Phase 1: Backend - Historical Growth Rate Calculator {#phase-1}

**Justification:** Foundation for all projections. Calculates historical wealth accumulation rate from past net worth data, ensuring sufficient data quality and handling edge cases.

### 1.1 Create Growth Rate Calculator Module

- [ ] Create `app/models/net_worth/growth_calculator.rb`

**Novel Implementation - Full Detail Required:**

```ruby
# app/models/net_worth/growth_calculator.rb

# Calculates historical growth rate of net worth based on past data points.
# Requires minimum 6 months of historical data for reliable projections.
#
# @example Basic usage
#   calculator = NetWorth::GrowthCalculator.new(family)
#   result = calculator.calculate
#   if result[:sufficient_data]
#     puts "Monthly growth: #{result[:monthly_rate]}"
#   end
#
# @example With custom parameters
#   calculator = NetWorth::GrowthCalculator.new(family, minimum_months: 12)
#   result = calculator.calculate(method: :median)
class NetWorth::GrowthCalculator
  attr_reader :family, :minimum_months

  # Supported calculation methods for growth rate
  CALCULATION_METHODS = [:mean, :median, :weighted].freeze

  # Minimum data points required for reliable calculations
  DEFAULT_MINIMUM_MONTHS = 6

  # @param family [Family] The family to calculate growth rate for
  # @param minimum_months [Integer] Minimum months of data required (default: 6)
  def initialize(family, minimum_months: DEFAULT_MINIMUM_MONTHS)
    @family = family
    @minimum_months = minimum_months
  end

  # Calculate historical growth rate
  #
  # @param method [Symbol] Calculation method (:mean, :median, :weighted)
  # @return [Hash] Growth rate data and metadata
  #
  # @example Return structure
  #   {
  #     sufficient_data: true,
  #     monthly_rate: Money.new(500, "USD"),
  #     monthly_rate_percent: 2.5,
  #     data_points_used: 12,
  #     calculation_method: :mean,
  #     historical_period: { start_date: Date, end_date: Date },
  #     volatility: :low, # :low, :medium, :high
  #     warning: nil # or String describing data quality issues
  #   }
  def calculate(method: :mean)
    raise ArgumentError, "Invalid method: #{method}" unless CALCULATION_METHODS.include?(method)

    # Get historical net worth data
    historical_data = fetch_historical_data

    # Validate data sufficiency
    validation = validate_data_sufficiency(historical_data)
    return validation unless validation[:sufficient_data]

    # Calculate month-over-month changes
    monthly_changes = calculate_monthly_changes(historical_data)

    # Calculate growth rate using specified method
    growth_rate = case method
    when :mean
      calculate_mean_growth(monthly_changes)
    when :median
      calculate_median_growth(monthly_changes)
    when :weighted
      calculate_weighted_growth(monthly_changes)
    end

    # Calculate volatility
    volatility = calculate_volatility(monthly_changes, growth_rate)

    # Detect warnings
    warning = detect_warnings(historical_data, monthly_changes, volatility)

    {
      sufficient_data: true,
      monthly_rate: growth_rate,
      monthly_rate_percent: calculate_percentage_rate(historical_data, growth_rate),
      data_points_used: historical_data.length,
      calculation_method: method,
      historical_period: {
        start_date: historical_data.first[:date],
        end_date: historical_data.last[:date]
      },
      volatility: volatility,
      warning: warning
    }
  end

  # Check if family has sufficient data for projections
  #
  # @return [Boolean] True if minimum data requirements are met
  def sufficient_data?
    historical_data = fetch_historical_data
    validation = validate_data_sufficiency(historical_data)
    validation[:sufficient_data]
  end

  private

    # Fetch historical net worth data points
    #
    # @return [Array<Hash>] Array of {date: Date, value: Money} hashes
    #
    # @note Fetches monthly snapshots going back from today
    def fetch_historical_data
      end_date = Date.current
      # Look back far enough to ensure we have minimum_months of data
      start_date = end_date - (minimum_months + 3).months

      net_worth_service = NetWorth.new(family)

      # Generate monthly data points
      data_points = []
      current_date = start_date.end_of_month

      while current_date <= end_date
        value = net_worth_service.calculate(date: current_date)
        data_points << { date: current_date, value: value }
        current_date = (current_date + 1.month).end_of_month
      end

      data_points
    end

    # Validate that we have sufficient data quality and quantity
    #
    # @param data_points [Array<Hash>] Historical data points
    # @return [Hash] Validation result
    def validate_data_sufficiency(data_points)
      if data_points.length < minimum_months
        return {
          sufficient_data: false,
          error: :insufficient_history,
          message: "At least #{minimum_months} months of transaction history required. Found #{data_points.length} months.",
          data_points_found: data_points.length,
          data_points_required: minimum_months
        }
      end

      # Check for zero or null values
      invalid_points = data_points.select { |point| point[:value].nil? || point[:value].zero? }
      if invalid_points.length > data_points.length * 0.3 # More than 30% invalid
        return {
          sufficient_data: false,
          error: :poor_data_quality,
          message: "Too many periods with zero or missing net worth data. Projections may be unreliable.",
          invalid_count: invalid_points.length,
          total_count: data_points.length
        }
      end

      { sufficient_data: true }
    end

    # Calculate month-over-month changes
    #
    # @param data_points [Array<Hash>] Historical data points
    # @return [Array<Money>] Array of monthly change amounts
    def calculate_monthly_changes(data_points)
      changes = []

      data_points.each_cons(2) do |previous, current|
        change = current[:value] - previous[:value]
        changes << change
      end

      changes
    end

    # Calculate mean (average) growth rate
    #
    # @param changes [Array<Money>] Monthly change amounts
    # @return [Money] Average monthly growth
    def calculate_mean_growth(changes)
      return Money.new(0, family.currency) if changes.empty?

      total = changes.reduce(Money.new(0, family.currency)) { |sum, change| sum + change }
      average_cents = total.cents / changes.length

      Money.new(average_cents, family.currency)
    end

    # Calculate median growth rate (more resistant to outliers)
    #
    # @param changes [Array<Money>] Monthly change amounts
    # @return [Money] Median monthly growth
    def calculate_median_growth(changes)
      return Money.new(0, family.currency) if changes.empty?

      sorted_cents = changes.map(&:cents).sort
      middle = sorted_cents.length / 2

      median_cents = if sorted_cents.length.odd?
        sorted_cents[middle]
      else
        (sorted_cents[middle - 1] + sorted_cents[middle]) / 2
      end

      Money.new(median_cents, family.currency)
    end

    # Calculate weighted growth rate (recent months weighted more heavily)
    #
    # @param changes [Array<Money>] Monthly change amounts
    # @return [Money] Weighted monthly growth
    #
    # @note Uses linear weighting: most recent month has weight N, oldest has weight 1
    def calculate_weighted_growth(changes)
      return Money.new(0, family.currency) if changes.empty?

      weighted_sum = 0
      weight_sum = 0

      changes.each_with_index do |change, index|
        weight = index + 1 # Earlier months have lower weight
        weighted_sum += change.cents * weight
        weight_sum += weight
      end

      weighted_average_cents = weighted_sum / weight_sum
      Money.new(weighted_average_cents, family.currency)
    end

    # Calculate percentage growth rate relative to net worth
    #
    # @param data_points [Array<Hash>] Historical data points
    # @param growth_rate [Money] Monthly growth rate
    # @return [Float] Percentage growth rate
    def calculate_percentage_rate(data_points, growth_rate)
      return 0.0 if data_points.empty?

      # Use average net worth over the period as base
      average_net_worth_cents = data_points.map { |p| p[:value].cents }.sum / data_points.length
      return 0.0 if average_net_worth_cents.zero?

      (growth_rate.cents.to_f / average_net_worth_cents * 100).round(2)
    end

    # Calculate volatility of growth rate
    #
    # @param changes [Array<Money>] Monthly change amounts
    # @param growth_rate [Money] Average growth rate
    # @return [Symbol] :low, :medium, or :high
    #
    # @note Uses coefficient of variation (standard deviation / mean) to classify volatility
    def calculate_volatility(changes, growth_rate)
      return :low if changes.empty? || growth_rate.zero?

      # Calculate standard deviation
      mean_cents = growth_rate.cents
      squared_diffs = changes.map { |change| (change.cents - mean_cents) ** 2 }
      variance = squared_diffs.sum / changes.length
      std_dev = Math.sqrt(variance)

      # Coefficient of variation
      cv = std_dev / mean_cents.abs

      if cv < 0.5
        :low
      elsif cv < 1.5
        :medium
      else
        :high
      end
    end

    # Detect data quality warnings
    #
    # @param data_points [Array<Hash>] Historical data points
    # @param changes [Array<Money>] Monthly change amounts
    # @param volatility [Symbol] Volatility classification
    # @return [String, nil] Warning message or nil
    def detect_warnings(data_points, changes, volatility)
      warnings = []

      # Check for recent negative trend
      recent_changes = changes.last(3)
      if recent_changes.length >= 3 && recent_changes.all? { |c| c.negative? }
        warnings << "Recent 3 months show declining net worth. Projections may be pessimistic."
      end

      # Warn about high volatility
      if volatility == :high
        warnings << "High volatility detected in historical data. Projections should be treated as rough estimates."
      end

      # Check for stagnant growth
      if changes.all? { |c| c.cents.abs < 100 } # Less than $1 change per month
        warnings << "Minimal historical growth detected. Projections may not be meaningful."
      end

      warnings.empty? ? nil : warnings.join(" ")
    end
end
```

### 1.2 Add Tests for Growth Calculator

- [ ] Create `test/models/net_worth/growth_calculator_test.rb`

**Novel Testing Logic - Full Detail Required:**

```ruby
# test/models/net_worth/growth_calculator_test.rb
require "test_helper"

class NetWorth::GrowthCalculatorTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @calculator = NetWorth::GrowthCalculator.new(@family)

    # Create test account
    @account = accounts(:checking)

    travel_to Date.new(2024, 6, 15)
  end

  teardown do
    travel_back
  end

  test "returns insufficient data when less than 6 months available" do
    # Create only 3 months of balance data
    3.times do |i|
      Balance.create!(
        account: @account,
        date: Date.new(2024, i + 1, 1).end_of_month,
        balance: 1000 + (i * 100),
        end_balance: 1000 + (i * 100)
      )
    end

    result = @calculator.calculate

    assert_not result[:sufficient_data]
    assert_equal :insufficient_history, result[:error]
    assert_includes result[:message], "At least 6 months"
  end

  test "calculates mean growth rate with sufficient data" do
    # Create 12 months of steadily increasing balances
    12.times do |i|
      Balance.create!(
        account: @account,
        date: Date.new(2023, i + 1, 1).end_of_month,
        balance: 10000 + (i * 500), # $500/month growth
        end_balance: 10000 + (i * 500)
      )
    end

    result = @calculator.calculate(method: :mean)

    assert result[:sufficient_data]
    assert_equal :mean, result[:calculation_method]
    assert_equal 12, result[:data_points_used]

    # Should be approximately $500/month
    assert_in_delta 500.0, result[:monthly_rate].to_f, 50.0
  end

  test "calculates median growth rate resistant to outliers" do
    # Create data with outliers
    balances = [10000, 10500, 11000, 15000, 11500, 12000, 12500, 13000]
    balances.each_with_index do |balance, i|
      Balance.create!(
        account: @account,
        date: Date.new(2023, i + 1, 1).end_of_month,
        balance: balance,
        end_balance: balance
      )
    end

    mean_result = @calculator.calculate(method: :mean)
    median_result = @calculator.calculate(method: :median)

    # Median should be less affected by the outlier at month 4
    assert median_result[:monthly_rate].to_f < mean_result[:monthly_rate].to_f
  end

  test "detects high volatility in erratic growth patterns" do
    # Create erratic growth pattern
    balances = [10000, 12000, 9000, 14000, 8000, 15000, 10000, 16000]
    balances.each_with_index do |balance, i|
      Balance.create!(
        account: @account,
        date: Date.new(2023, i + 1, 1).end_of_month,
        balance: balance,
        end_balance: balance
      )
    end

    result = @calculator.calculate

    assert_equal :high, result[:volatility]
    assert_not_nil result[:warning]
    assert_includes result[:warning], "volatility"
  end

  test "warns about recent negative trend" do
    # Create overall positive growth but recent decline
    balances = [10000, 11000, 12000, 13000, 14000, 15000, 14500, 14000, 13500]
    balances.each_with_index do |balance, i|
      Balance.create!(
        account: @account,
        date: Date.new(2023, i + 1, 1).end_of_month,
        balance: balance,
        end_balance: balance
      )
    end

    result = @calculator.calculate

    assert result[:sufficient_data]
    assert_not_nil result[:warning]
    assert_includes result[:warning], "declining"
  end

  test "calculates percentage growth rate" do
    # Create steady 5% monthly growth
    6.times do |i|
      balance = 10000 * (1.05 ** i)
      Balance.create!(
        account: @account,
        date: Date.new(2024, i + 1, 1).end_of_month,
        balance: balance.round,
        end_balance: balance.round
      )
    end

    result = @calculator.calculate

    # Should be approximately 5% monthly growth
    assert_in_delta 5.0, result[:monthly_rate_percent], 1.0
  end

  test "handles negative growth" do
    # Create declining net worth
    6.times do |i|
      Balance.create!(
        account: @account,
        date: Date.new(2024, i + 1, 1).end_of_month,
        balance: 10000 - (i * 300),
        end_balance: 10000 - (i * 300)
      )
    end

    result = @calculator.calculate

    assert result[:sufficient_data]
    assert result[:monthly_rate].negative?
  end

  test "sufficient_data? returns boolean check" do
    assert_not @calculator.sufficient_data?

    # Add sufficient data
    12.times do |i|
      Balance.create!(
        account: @account,
        date: Date.new(2023, i + 1, 1).end_of_month,
        balance: 10000 + (i * 100),
        end_balance: 10000 + (i * 100)
      )
    end

    assert @calculator.sufficient_data?
  end
end
```

---

## Phase 2: Backend - Projection Engine {#phase-2}

**Justification:** Core projection logic generating future net worth estimates. Implements linear growth algorithm with three scenarios (conservative, realistic, optimistic) across user-selected timeframes.

### 2.1 Create Projection Engine Module

- [ ] Create `app/models/net_worth/projection_engine.rb`

**Novel Implementation - Full Detail Required:**

```ruby
# app/models/net_worth/projection_engine.rb

# Generates future net worth projections based on historical growth rate.
# Produces three scenarios: conservative (70%), realistic (100%), optimistic (130%).
#
# @example Basic usage
#   engine = NetWorth::ProjectionEngine.new(family)
#   projections = engine.generate(timeframes: [1, 5, 10])
#   projections[:realistic][:values].each { |point| puts "#{point[:date]}: #{point[:value]}" }
#
# @example With custom growth rate
#   engine = NetWorth::ProjectionEngine.new(family, monthly_growth_rate: Money.new(1000, "USD"))
#   projections = engine.generate(timeframes: [5])
class NetWorth::ProjectionEngine
  attr_reader :family, :monthly_growth_rate

  # Scenario multipliers applied to base growth rate
  SCENARIO_MULTIPLIERS = {
    conservative: 0.70,
    realistic: 1.00,
    optimistic: 1.30
  }.freeze

  # Available projection timeframes (in years)
  AVAILABLE_TIMEFRAMES = [1, 2, 3, 5, 10, 20].freeze

  # Default projection interval (monthly)
  DEFAULT_INTERVAL = :monthly

  # @param family [Family] The family to project for
  # @param monthly_growth_rate [Money, nil] Override growth rate (if nil, calculates from history)
  def initialize(family, monthly_growth_rate: nil)
    @family = family
    @monthly_growth_rate = monthly_growth_rate
  end

  # Generate projections for specified timeframes
  #
  # @param timeframes [Array<Integer>] Years to project (e.g., [1, 5, 10])
  # @param interval [Symbol] Data point interval (:monthly, :quarterly, :yearly)
  # @return [Hash] Projection data structure
  #
  # @example Return structure
  #   {
  #     current_net_worth: Money.new(50000, "USD"),
  #     growth_rate: {
  #       monthly: Money.new(500, "USD"),
  #       annual: Money.new(6000, "USD"),
  #       percent: 1.2
  #     },
  #     data_quality: {
  #       sufficient_data: true,
  #       volatility: :low,
  #       warning: nil
  #     },
  #     scenarios: {
  #       conservative: { values: [...], final_value: Money, total_growth: Money },
  #       realistic: { values: [...], final_value: Money, total_growth: Money },
  #       optimistic: { values: [...], final_value: Money, total_growth: Money }
  #     },
  #     timeframes: [1, 5, 10]
  #   }
  def generate(timeframes: [1, 5, 10], interval: DEFAULT_INTERVAL)
    validate_timeframes!(timeframes)

    # Get current net worth
    net_worth_service = NetWorth.new(family)
    current_value = net_worth_service.calculate(date: Date.current)

    # Calculate or use provided growth rate
    growth_data = calculate_growth_rate

    # Return early if insufficient data
    unless growth_data[:sufficient_data]
      return {
        current_net_worth: current_value,
        data_quality: growth_data,
        error: growth_data[:error],
        message: growth_data[:message]
      }
    end

    monthly_rate = growth_data[:monthly_rate]

    # Generate projections for each scenario
    scenarios = {}
    SCENARIO_MULTIPLIERS.each do |scenario_name, multiplier|
      scenario_rate = Money.new((monthly_rate.cents * multiplier).round, family.currency)
      scenarios[scenario_name] = generate_scenario_projection(
        current_value: current_value,
        monthly_rate: scenario_rate,
        timeframes: timeframes,
        interval: interval
      )
    end

    {
      current_net_worth: current_value,
      growth_rate: {
        monthly: monthly_rate,
        annual: Money.new(monthly_rate.cents * 12, family.currency),
        percent: growth_data[:monthly_rate_percent]
      },
      data_quality: {
        sufficient_data: true,
        volatility: growth_data[:volatility],
        warning: growth_data[:warning],
        data_points_used: growth_data[:data_points_used],
        historical_period: growth_data[:historical_period]
      },
      scenarios: scenarios,
      timeframes: timeframes.sort
    }
  end

  # Check if projections can be generated
  #
  # @return [Boolean] True if sufficient historical data exists
  def can_project?
    growth_data = calculate_growth_rate
    growth_data[:sufficient_data]
  end

  private

    # Validate requested timeframes
    #
    # @param timeframes [Array<Integer>] Requested timeframes
    # @raise [ArgumentError] If invalid timeframes provided
    def validate_timeframes!(timeframes)
      if timeframes.empty?
        raise ArgumentError, "At least one timeframe must be specified"
      end

      invalid = timeframes.reject { |tf| AVAILABLE_TIMEFRAMES.include?(tf) }
      unless invalid.empty?
        raise ArgumentError, "Invalid timeframes: #{invalid.join(', ')}. Available: #{AVAILABLE_TIMEFRAMES.join(', ')}"
      end
    end

    # Calculate growth rate using GrowthCalculator
    #
    # @return [Hash] Growth rate data from GrowthCalculator
    def calculate_growth_rate
      return { sufficient_data: true, monthly_rate: @monthly_growth_rate, volatility: :low, warning: nil } if @monthly_growth_rate

      calculator = NetWorth::GrowthCalculator.new(family)
      calculator.calculate(method: :mean)
    end

    # Generate projection data for a single scenario
    #
    # @param current_value [Money] Starting net worth
    # @param monthly_rate [Money] Monthly growth rate for this scenario
    # @param timeframes [Array<Integer>] Years to project
    # @param interval [Symbol] Data point interval
    # @return [Hash] Scenario projection data
    def generate_scenario_projection(current_value:, monthly_rate:, timeframes:, interval:)
      max_years = timeframes.max

      # Generate date points based on interval
      dates = generate_projection_dates(
        start_date: Date.current,
        years: max_years,
        interval: interval
      )

      # Calculate projected values using linear growth
      values = []
      dates.each do |date|
        months_elapsed = months_between(Date.current, date)
        projected_value = current_value + (monthly_rate * months_elapsed)

        values << {
          date: date,
          value: projected_value,
          months_from_now: months_elapsed
        }
      end

      # Extract milestone values for requested timeframes
      milestones = {}
      timeframes.each do |years|
        target_date = Date.current + years.years
        # Find closest data point to target date
        milestone_point = values.min_by { |v| (v[:date] - target_date).abs }
        milestones[years] = {
          date: milestone_point[:date],
          value: milestone_point[:value],
          growth_from_current: milestone_point[:value] - current_value
        }
      end

      # Calculate final value (at max timeframe)
      final_point = values.last
      final_value = final_point[:value]
      total_growth = final_value - current_value

      {
        values: values,
        milestones: milestones,
        final_value: final_value,
        total_growth: total_growth,
        years_projected: max_years
      }
    end

    # Generate array of projection dates based on interval
    #
    # @param start_date [Date] Projection start date
    # @param years [Integer] Number of years to project
    # @param interval [Symbol] Interval between data points
    # @return [Array<Date>] Array of projection dates
    def generate_projection_dates(start_date:, years:, interval:)
      end_date = start_date + years.years
      dates = []
      current_date = start_date

      case interval
      when :monthly
        while current_date <= end_date
          dates << current_date
          current_date = current_date + 1.month
        end
      when :quarterly
        while current_date <= end_date
          dates << current_date
          current_date = current_date + 3.months
        end
      when :yearly
        while current_date <= end_date
          dates << current_date
          current_date = current_date + 1.year
        end
      else
        raise ArgumentError, "Invalid interval: #{interval}"
      end

      dates
    end

    # Calculate months between two dates
    #
    # @param start_date [Date] Start date
    # @param end_date [Date] End date
    # @return [Integer] Number of months
    def months_between(start_date, end_date)
      ((end_date.year - start_date.year) * 12) + (end_date.month - start_date.month)
    end
end
```

### 2.2 Add Tests for Projection Engine

- [ ] Create `test/models/net_worth/projection_engine_test.rb`

**Novel Testing Logic - Full Detail Required:**

```ruby
# test/models/net_worth/projection_engine_test.rb
require "test_helper"

class NetWorth::ProjectionEngineTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @account = accounts(:checking)

    # Create 12 months of historical data with $500/month growth
    travel_to Date.new(2024, 6, 15)

    12.times do |i|
      Balance.create!(
        account: @account,
        date: Date.new(2023, i + 1, 1).end_of_month,
        balance: 10000 + (i * 500),
        end_balance: 10000 + (i * 500)
      )
    end
  end

  teardown do
    travel_back
  end

  test "generates projections for requested timeframes" do
    engine = NetWorth::ProjectionEngine.new(@family)
    result = engine.generate(timeframes: [1, 5, 10])

    assert result[:scenarios][:realistic].present?
    assert result[:scenarios][:conservative].present?
    assert result[:scenarios][:optimistic].present?

    assert_equal [1, 5, 10], result[:timeframes]
  end

  test "realistic scenario uses 100% of growth rate" do
    engine = NetWorth::ProjectionEngine.new(@family)
    result = engine.generate(timeframes: [1])

    realistic = result[:scenarios][:realistic]
    current = result[:current_net_worth]
    monthly_rate = result[:growth_rate][:monthly]

    # After 1 year (12 months), should add 12 * monthly_rate
    one_year_milestone = realistic[:milestones][1]
    expected_value = current + (monthly_rate * 12)

    assert_in_delta expected_value.cents, one_year_milestone[:value].cents, 100
  end

  test "conservative scenario uses 70% of growth rate" do
    engine = NetWorth::ProjectionEngine.new(@family)
    result = engine.generate(timeframes: [1])

    conservative = result[:scenarios][:conservative]
    realistic = result[:scenarios][:realistic]

    # Conservative should be less than realistic
    assert conservative[:final_value] < realistic[:final_value]

    # Should be approximately 70% of realistic growth
    conservative_growth = conservative[:total_growth].cents
    realistic_growth = realistic[:total_growth].cents

    assert_in_delta 0.70, (conservative_growth.to_f / realistic_growth), 0.05
  end

  test "optimistic scenario uses 130% of growth rate" do
    engine = NetWorth::ProjectionEngine.new(@family)
    result = engine.generate(timeframes: [1])

    optimistic = result[:scenarios][:optimistic]
    realistic = result[:scenarios][:realistic]

    # Optimistic should be more than realistic
    assert optimistic[:final_value] > realistic[:final_value]

    # Should be approximately 130% of realistic growth
    optimistic_growth = optimistic[:total_growth].cents
    realistic_growth = realistic[:total_growth].cents

    assert_in_delta 1.30, (optimistic_growth.to_f / realistic_growth), 0.05
  end

  test "returns error when insufficient historical data" do
    # Clear balances to simulate insufficient data
    Balance.destroy_all

    engine = NetWorth::ProjectionEngine.new(@family)
    result = engine.generate(timeframes: [1])

    assert_not result[:data_quality][:sufficient_data]
    assert result[:error].present?
    assert result[:message].present?
  end

  test "includes data quality information" do
    engine = NetWorth::ProjectionEngine.new(@family)
    result = engine.generate(timeframes: [1])

    assert result[:data_quality][:sufficient_data]
    assert_includes [:low, :medium, :high], result[:data_quality][:volatility]
    assert result[:data_quality][:data_points_used] >= 6
  end

  test "can_project? returns boolean" do
    engine = NetWorth::ProjectionEngine.new(@family)
    assert engine.can_project?

    Balance.destroy_all
    engine2 = NetWorth::ProjectionEngine.new(@family)
    assert_not engine2.can_project?
  end

  test "supports custom growth rate override" do
    custom_rate = Money.new(1000_00, @family.currency) # $1000/month
    engine = NetWorth::ProjectionEngine.new(@family, monthly_growth_rate: custom_rate)
    result = engine.generate(timeframes: [1])

    assert_equal custom_rate, result[:growth_rate][:monthly]
  end

  test "generates monthly data points for projections" do
    engine = NetWorth::ProjectionEngine.new(@family)
    result = engine.generate(timeframes: [1], interval: :monthly)

    realistic_values = result[:scenarios][:realistic][:values]

    # Should have approximately 12 data points for 1 year
    assert_operator realistic_values.length, :>=, 12
    assert_operator realistic_values.length, :<=, 13
  end

  test "validates timeframe parameters" do
    engine = NetWorth::ProjectionEngine.new(@family)

    assert_raises(ArgumentError) do
      engine.generate(timeframes: [])
    end

    assert_raises(ArgumentError) do
      engine.generate(timeframes: [100]) # Not in AVAILABLE_TIMEFRAMES
    end
  end

  test "includes milestone data for each timeframe" do
    engine = NetWorth::ProjectionEngine.new(@family)
    result = engine.generate(timeframes: [1, 5, 10])

    realistic = result[:scenarios][:realistic]

    assert realistic[:milestones][1].present?
    assert realistic[:milestones][5].present?
    assert realistic[:milestones][10].present?

    # Each milestone should have date, value, and growth
    milestone = realistic[:milestones][1]
    assert milestone[:date].is_a?(Date)
    assert milestone[:value].is_a?(Money)
    assert milestone[:growth_from_current].is_a?(Money)
  end
end
```

---

## Phase 3: Backend - Service Integration {#phase-3}

**Justification:** Integrates projection capabilities into existing NetWorth service class, providing unified interface for both historical and projection data.

### 3.1 Extend NetWorth Service with Projection Methods

- [ ] Update `app/models/net_worth.rb` to include projection methods

**Standard Pattern - Reference Existing:**

The existing `NetWorth` class (app/models/net_worth.rb) handles historical net worth calculations. Follow the established pattern:
- Instance initialized with `family`
- Public methods return data structures suitable for controllers/views
- Private methods handle internal calculations
- Use `Money` objects for currency values

**Differences from existing pattern:**
- Add delegation to new projection modules
- Add combined method returning both historical and projection data
- Add convenience methods for checking projection availability

**Novel Methods - Full Detail Required:**

```ruby
# Add to app/models/net_worth.rb

# Generate future net worth projections
#
# @param timeframes [Array<Integer>] Years to project (default: [1, 5, 10])
# @param interval [Symbol] Data point interval (default: :monthly)
# @return [Hash] Projection data with all scenarios
#
# @example Basic usage
#   net_worth = NetWorth.new(family)
#   projections = net_worth.projections(timeframes: [1, 5, 10])
#   puts projections[:scenarios][:realistic][:milestones][5][:value]
#
# @note Requires at least 6 months of historical transaction data
def projections(timeframes: [1, 5, 10], interval: :monthly)
  engine = NetWorth::ProjectionEngine.new(family)
  engine.generate(timeframes: timeframes, interval: interval)
end

# Generate combined dataset with historical data and projections
#
# @param historical_period [Period, nil] Period for historical data (default: last 12 months)
# @param projection_timeframes [Array<Integer>] Years to project (default: [1, 5, 10])
# @return [Hash] Combined historical and projection data
#
# @example Return structure
#   {
#     current_net_worth: Money,
#     historical: {
#       data_points: [...],
#       summary: {...}
#     },
#     projections: {
#       scenarios: {...},
#       data_quality: {...}
#     }
#   }
def combined_timeline(historical_period: nil, projection_timeframes: [1, 5, 10])
  # Default to last 12 months of history
  historical_period ||= Period.custom(
    start_date: 12.months.ago.to_date,
    end_date: Date.current
  )

  # Get historical data
  historical_data = timeline(
    start_date: historical_period.date_range.first,
    end_date: historical_period.date_range.last,
    interval: :monthly
  )

  # Get projections
  projection_data = projections(timeframes: projection_timeframes)

  {
    current_net_worth: current,
    historical: {
      data_points: historical_data[:data_points],
      summary: historical_data[:summary]
    },
    projections: projection_data
  }
end

# Check if family has sufficient data for projections
#
# @return [Boolean] True if projections can be generated
def can_project?
  calculator = NetWorth::GrowthCalculator.new(family)
  calculator.sufficient_data?
end

# Get growth rate information
#
# @return [Hash] Growth rate data including monthly rate, annual rate, and volatility
def growth_rate_info
  calculator = NetWorth::GrowthCalculator.new(family)
  result = calculator.calculate

  return { error: result[:error], message: result[:message] } unless result[:sufficient_data]

  {
    monthly_rate: result[:monthly_rate],
    annual_rate: Money.new(result[:monthly_rate].cents * 12, family.currency),
    percent: result[:monthly_rate_percent],
    volatility: result[:volatility],
    warning: result[:warning]
  }
end
```

### 3.2 Add Tests for NetWorth Service Integration

- [ ] Add tests to `test/models/net_worth_test.rb`

**Standard Pattern:**

```ruby
# Add to test/models/net_worth_test.rb

test "projections returns projection data with all scenarios" do
  # Create 12 months of balance history
  12.times do |i|
    Balance.create!(
      account: @checking,
      date: Date.new(2023, i + 1, 1).end_of_month,
      balance: 10000 + (i * 500),
      end_balance: 10000 + (i * 500)
    )
  end

  projections = @net_worth.projections(timeframes: [1, 5])

  assert projections[:scenarios][:realistic].present?
  assert projections[:scenarios][:conservative].present?
  assert projections[:scenarios][:optimistic].present?
  assert_equal [1, 5], projections[:timeframes]
end

test "combined_timeline returns both historical and projection data" do
  # Create historical data
  12.times do |i|
    Balance.create!(
      account: @checking,
      date: Date.new(2023, i + 1, 1).end_of_month,
      balance: 10000 + (i * 500),
      end_balance: 10000 + (i * 500)
    )
  end

  result = @net_worth.combined_timeline

  assert result[:historical].present?
  assert result[:projections].present?
  assert result[:current_net_worth].is_a?(Money)
end

test "can_project? returns true with sufficient data" do
  assert_not @net_worth.can_project?

  12.times do |i|
    Balance.create!(
      account: @checking,
      date: Date.new(2023, i + 1, 1).end_of_month,
      balance: 10000 + (i * 100),
      end_balance: 10000 + (i * 100)
    )
  end

  assert @net_worth.can_project?
end

test "growth_rate_info returns rate and volatility data" do
  12.times do |i|
    Balance.create!(
      account: @checking,
      date: Date.new(2023, i + 1, 1).end_of_month,
      balance: 10000 + (i * 500),
      end_balance: 10000 + (i * 500)
    )
  end

  info = @net_worth.growth_rate_info

  assert info[:monthly_rate].is_a?(Money)
  assert info[:annual_rate].is_a?(Money)
  assert info[:percent].is_a?(Float)
  assert_includes [:low, :medium, :high], info[:volatility]
end
```

---

## Phase 4: Controller - Home Page Data Endpoint {#phase-4}

**Justification:** Provides data endpoint for Home page Net Worth card to fetch projection data. Follows existing controller patterns for JSON responses.

### 4.1 Add Projection Action to Pages Controller

- [ ] Update `app/controllers/pages_controller.rb` to include projection endpoint

**Standard Pattern - Reference Existing:**

Follow the pattern from other JSON-returning controller actions in the codebase. Use:
- `respond_to` block for JSON format
- Instance variables for view/JSON data
- Proper error handling for insufficient data

**Novel Action - Full Detail Required:**

```ruby
# Add to app/controllers/pages_controller.rb

# GET /net_worth_projections
# Returns net worth projection data for Home page card
def net_worth_projections
  timeframes = parse_timeframe_params

  net_worth = NetWorth.new(Current.family)

  # Check if projections can be generated
  unless net_worth.can_project?
    render json: {
      error: "insufficient_data",
      message: I18n.t("net_worth.projections.insufficient_data")
    }, status: :unprocessable_entity
    return
  end

  # Generate projections
  @projections = net_worth.projections(timeframes: timeframes)
  @current_net_worth = net_worth.current

  respond_to do |format|
    format.json do
      render json: {
        current_net_worth: {
          amount: @current_net_worth.to_s,
          formatted: @current_net_worth.format
        },
        growth_rate: {
          monthly: {
            amount: @projections[:growth_rate][:monthly].to_s,
            formatted: @projections[:growth_rate][:monthly].format
          },
          annual: {
            amount: @projections[:growth_rate][:annual].to_s,
            formatted: @projections[:growth_rate][:annual].format
          },
          percent: @projections[:growth_rate][:percent]
        },
        scenarios: format_scenarios_for_json(@projections[:scenarios]),
        data_quality: @projections[:data_quality],
        timeframes: @projections[:timeframes]
      }
    end
  end
end

private

  # Parse timeframe parameters from request
  #
  # @return [Array<Integer>] Array of timeframe years
  def parse_timeframe_params
    if params[:timeframes].present?
      params[:timeframes].split(',').map(&:to_i).select { |t| t > 0 }
    else
      [1, 5, 10] # Default timeframes
    end
  end

  # Format scenario data for JSON response
  #
  # @param scenarios [Hash] Scenario data from projection engine
  # @return [Hash] JSON-ready scenario data
  def format_scenarios_for_json(scenarios)
    formatted = {}

    scenarios.each do |scenario_name, scenario_data|
      formatted[scenario_name] = {
        milestones: format_milestones(scenario_data[:milestones]),
        values: format_projection_values(scenario_data[:values]),
        final_value: {
          amount: scenario_data[:final_value].to_s,
          formatted: scenario_data[:final_value].format
        },
        total_growth: {
          amount: scenario_data[:total_growth].to_s,
          formatted: scenario_data[:total_growth].format
        }
      }
    end

    formatted
  end

  # Format milestone data for JSON
  #
  # @param milestones [Hash] Milestone data by year
  # @return [Hash] JSON-ready milestone data
  def format_milestones(milestones)
    formatted = {}

    milestones.each do |years, milestone_data|
      formatted[years] = {
        date: milestone_data[:date].strftime("%Y-%m-%d"),
        value: {
          amount: milestone_data[:value].to_s,
          formatted: milestone_data[:value].format
        },
        growth_from_current: {
          amount: milestone_data[:growth_from_current].to_s,
          formatted: milestone_data[:growth_from_current].format
        }
      }
    end

    formatted
  end

  # Format projection value points for chart
  #
  # @param values [Array<Hash>] Projection data points
  # @return [Array<Hash>] JSON-ready chart data
  def format_projection_values(values)
    values.map do |point|
      {
        date: point[:date].strftime("%Y-%m-%d"),
        value: {
          amount: point[:value].to_s,
          formatted: point[:value].format
        },
        months_from_now: point[:months_from_now]
      }
    end
  end
```

### 4.2 Add Route

- [ ] Add route in `config/routes.rb`

**Standard Pattern:**

```ruby
# Add to config/routes.rb

get "net_worth_projections", to: "pages#net_worth_projections"
```

### 4.3 Add Controller Tests

- [ ] Add tests to `test/controllers/pages_controller_test.rb`

**Standard Pattern:**

```ruby
# Add to test/controllers/pages_controller_test.rb

test "should get net worth projections as json" do
  # Create sufficient historical data
  account = accounts(:checking)
  12.times do |i|
    Balance.create!(
      account: account,
      date: Date.new(2023, i + 1, 1).end_of_month,
      balance: 10000 + (i * 500),
      end_balance: 10000 + (i * 500)
    )
  end

  get net_worth_projections_url(format: :json)
  assert_response :success

  json = JSON.parse(response.body)
  assert json["current_net_worth"].present?
  assert json["scenarios"]["realistic"].present?
  assert json["scenarios"]["conservative"].present?
  assert json["scenarios"]["optimistic"].present?
end

test "returns error when insufficient data for projections" do
  get net_worth_projections_url(format: :json)
  assert_response :unprocessable_entity

  json = JSON.parse(response.body)
  assert_equal "insufficient_data", json["error"]
end

test "respects timeframe parameters" do
  account = accounts(:checking)
  12.times do |i|
    Balance.create!(
      account: account,
      date: Date.new(2023, i + 1, 1).end_of_month,
      balance: 10000 + (i * 500),
      end_balance: 10000 + (i * 500)
    )
  end

  get net_worth_projections_url(timeframes: "1,5,20", format: :json)
  assert_response :success

  json = JSON.parse(response.body)
  assert_equal [1, 5, 20], json["timeframes"]
end
```

---

## Phase 5: Frontend - Enhanced Net Worth Card {#phase-5}

**Justification:** Enhances existing Home page Net Worth card to display future projections. Provides expandable section with timeframe selection and scenario toggles.

### 5.1 Update Home Page View Component

- [ ] Locate existing Net Worth card component or partial on Home page
- [ ] Add expandable projections section

**Standard Pattern - Reference Existing:**

Follow existing Home page component patterns (likely in `app/views/pages/home.html.erb` or a ViewComponent). Use:
- Turbo Frames for dynamic loading
- Stimulus controller for interactivity
- Tailwind design system tokens
- `icon` helper for icons

**Novel Section - Full Detail Required:**

```erb
<%# Add to Net Worth card component/partial %>

<div class="bg-container border border-primary rounded-lg p-6">
  <%# Existing current net worth display %>
  <div class="flex items-center justify-between mb-4">
    <h3 class="text-lg font-semibold text-primary">
      <%= icon "wallet", class: "inline w-5 h-5 mr-2" %>
      <%= t("net_worth.current_title") %>
    </h3>
    <span class="text-2xl font-bold text-primary">
      <%= @current_net_worth.format %>
    </span>
  </div>

  <%# NEW: Projection section %>
  <div
    data-controller="net-worth-projection"
    data-net-worth-projection-can-project-value="<%= @can_project %>"
    class="mt-6 pt-6 border-t border-primary">

    <%# Toggle button %>
    <button
      data-action="click->net-worth-projection#toggleExpanded"
      data-net-worth-projection-target="toggleButton"
      class="flex items-center justify-between w-full text-left">
      <span class="text-sm font-medium text-primary">
        <%= t("net_worth.projections.title") %>
      </span>
      <%= icon "chevron-down",
          class: "w-4 h-4 text-subdued transition-transform",
          data: { net_worth_projection_target: "chevronIcon" } %>
    </button>

    <%# Expandable content %>
    <div
      data-net-worth-projection-target="content"
      class="hidden mt-4">

      <%# Insufficient data warning %>
      <div
        data-net-worth-projection-target="insufficientDataWarning"
        class="hidden p-4 bg-yellow-50 border border-yellow-200 rounded-lg">
        <p class="text-sm text-yellow-800">
          <%= icon "alert-circle", class: "inline w-4 h-4 mr-1" %>
          <%= t("net_worth.projections.insufficient_data") %>
        </p>
      </div>

      <%# Timeframe selector %>
      <div class="mb-4">
        <label class="block text-sm font-medium text-primary mb-2">
          <%= t("net_worth.projections.select_timeframes") %>
        </label>
        <div class="flex flex-wrap gap-2">
          <% [1, 2, 3, 5, 10, 20].each do |years| %>
            <label class="inline-flex items-center">
              <input
                type="checkbox"
                value="<%= years %>"
                data-action="change->net-worth-projection#updateTimeframes"
                data-net-worth-projection-target="timeframeCheckbox"
                <%= "checked" if [1, 5, 10].include?(years) %>
                class="rounded border-gray-300 text-blue-600 focus:ring-blue-500">
              <span class="ml-2 text-sm text-primary">
                <%= t("net_worth.projections.timeframe_years", count: years) %>
              </span>
            </label>
          <% end %>
        </div>
      </div>

      <%# Scenario toggles %>
      <div class="mb-4">
        <label class="block text-sm font-medium text-primary mb-2">
          <%= t("net_worth.projections.scenarios") %>
        </label>
        <div class="flex gap-4">
          <label class="inline-flex items-center">
            <input
              type="checkbox"
              value="conservative"
              data-action="change->net-worth-projection#updateScenarios"
              data-net-worth-projection-target="scenarioCheckbox"
              checked
              class="rounded border-gray-300 text-orange-600 focus:ring-orange-500">
            <span class="ml-2 text-sm text-primary">
              <%= t("net_worth.projections.scenario_conservative") %>
            </span>
          </label>
          <label class="inline-flex items-center">
            <input
              type="checkbox"
              value="realistic"
              data-action="change->net-worth-projection#updateScenarios"
              data-net-worth-projection-target="scenarioCheckbox"
              checked
              class="rounded border-gray-300 text-blue-600 focus:ring-blue-500">
            <span class="ml-2 text-sm text-primary">
              <%= t("net_worth.projections.scenario_realistic") %>
            </span>
          </label>
          <label class="inline-flex items-center">
            <input
              type="checkbox"
              value="optimistic"
              data-action="change->net-worth-projection#updateScenarios"
              data-net-worth-projection-target="scenarioCheckbox"
              checked
              class="rounded border-gray-300 text-green-600 focus:ring-green-500">
            <span class="ml-2 text-sm text-primary">
              <%= t("net_worth.projections.scenario_optimistic") %>
            </span>
          </label>
        </div>
      </div>

      <%# Loading state %>
      <div
        data-net-worth-projection-target="loadingIndicator"
        class="hidden flex items-center justify-center py-8">
        <%= icon "loader-2", class: "w-6 h-6 animate-spin text-subdued" %>
      </div>

      <%# Chart container %>
      <div
        data-net-worth-projection-target="chartContainer"
        class="h-64">
      </div>

      <%# Milestone summary %>
      <div
        data-net-worth-projection-target="milestones"
        class="mt-4 grid grid-cols-3 gap-4">
      </div>

      <%# Data quality warning %>
      <div
        data-net-worth-projection-target="qualityWarning"
        class="hidden mt-4 p-3 bg-blue-50 border border-blue-200 rounded-lg">
        <p class="text-xs text-blue-800" data-net-worth-projection-target="qualityWarningText"></p>
      </div>
    </div>
  </div>
</div>
```

### 5.2 Update Pages Controller to Include Projection Flag

- [ ] Update `app/controllers/pages_controller.rb` home action

**Standard Pattern:**

```ruby
# Update in app/controllers/pages_controller.rb

def home
  # ... existing code ...

  # Add projection availability check
  net_worth = NetWorth.new(Current.family)
  @current_net_worth = net_worth.current
  @can_project = net_worth.can_project?
end
```

---

## Phase 6: Frontend - Chart Visualization {#phase-6}

**Justification:** Implements interactive D3.js chart displaying both historical and projected net worth data with visual distinction between actual and projected values.

### 6.1 Create Net Worth Projection Stimulus Controller

- [ ] Create `app/javascript/controllers/net_worth_projection_controller.js`

**Novel Controller - Full Detail Required:**

```javascript
// app/javascript/controllers/net_worth_projection_controller.js

import { Controller } from "@hotwired/stimulus"
import * as d3 from "d3"

// Manages net worth projection display including timeframe selection,
// scenario toggling, and D3.js chart rendering
export default class extends Controller {
  static targets = [
    "content",
    "toggleButton",
    "chevronIcon",
    "timeframeCheckbox",
    "scenarioCheckbox",
    "chartContainer",
    "milestones",
    "loadingIndicator",
    "insufficientDataWarning",
    "qualityWarning",
    "qualityWarningText"
  ]

  static values = {
    canProject: Boolean
  }

  connect() {
    this.expanded = false
    this.projectionData = null

    // Chart configuration
    this.chartConfig = {
      margin: { top: 20, right: 20, bottom: 30, left: 60 },
      colors: {
        conservative: "#f97316", // orange
        realistic: "#3b82f6", // blue
        optimistic: "#10b981" // green
      },
      lineStyles: {
        historical: "solid",
        projection: "dashed"
      }
    }
  }

  toggleExpanded() {
    this.expanded = !this.expanded

    if (this.expanded) {
      this.contentTarget.classList.remove("hidden")
      this.chevronIconTarget.style.transform = "rotate(180deg)"

      // Load projection data if not already loaded
      if (!this.projectionData) {
        this.loadProjections()
      }
    } else {
      this.contentTarget.classList.add("hidden")
      this.chevronIconTarget.style.transform = "rotate(0deg)"
    }
  }

  updateTimeframes() {
    if (this.projectionData) {
      this.loadProjections()
    }
  }

  updateScenarios() {
    if (this.projectionData) {
      this.renderChart()
      this.renderMilestones()
    }
  }

  async loadProjections() {
    // Show loading state
    this.showLoading()

    // Get selected timeframes
    const timeframes = this.getSelectedTimeframes()

    if (timeframes.length === 0) {
      this.hideLoading()
      return
    }

    try {
      const response = await fetch(`/net_worth_projections.json?timeframes=${timeframes.join(',')}`)

      if (!response.ok) {
        const error = await response.json()
        if (error.error === "insufficient_data") {
          this.showInsufficientDataWarning()
        }
        this.hideLoading()
        return
      }

      this.projectionData = await response.json()

      // Show quality warning if present
      if (this.projectionData.data_quality?.warning) {
        this.showQualityWarning(this.projectionData.data_quality.warning)
      }

      this.renderChart()
      this.renderMilestones()
      this.hideLoading()
    } catch (error) {
      console.error("Failed to load projections:", error)
      this.hideLoading()
    }
  }

  getSelectedTimeframes() {
    return Array.from(this.timeframeCheckboxTargets)
      .filter(checkbox => checkbox.checked)
      .map(checkbox => parseInt(checkbox.value))
  }

  getSelectedScenarios() {
    return Array.from(this.scenarioCheckboxTargets)
      .filter(checkbox => checkbox.checked)
      .map(checkbox => checkbox.value)
  }

  renderChart() {
    const container = this.chartContainerTarget
    const selectedScenarios = this.getSelectedScenarios()

    // Clear existing chart
    d3.select(container).selectAll("*").remove()

    if (!this.projectionData || selectedScenarios.length === 0) {
      return
    }

    // Setup dimensions
    const containerRect = container.getBoundingClientRect()
    const width = containerRect.width
    const height = containerRect.height
    const { margin } = this.chartConfig

    const chartWidth = width - margin.left - margin.right
    const chartHeight = height - margin.top - margin.bottom

    // Create SVG
    const svg = d3.select(container)
      .append("svg")
      .attr("width", width)
      .attr("height", height)
      .append("g")
      .attr("transform", `translate(${margin.left},${margin.top})`)

    // Prepare data
    const allValues = []
    const currentDate = new Date()

    selectedScenarios.forEach(scenarioName => {
      const scenario = this.projectionData.scenarios[scenarioName]
      scenario.values.forEach(point => {
        allValues.push({
          date: new Date(point.date),
          value: parseFloat(point.value.amount),
          scenario: scenarioName
        })
      })
    })

    // Scales
    const xScale = d3.scaleTime()
      .domain(d3.extent(allValues, d => d.date))
      .range([0, chartWidth])

    const yScale = d3.scaleLinear()
      .domain([
        d3.min(allValues, d => d.value) * 0.95,
        d3.max(allValues, d => d.value) * 1.05
      ])
      .range([chartHeight, 0])

    // Axes
    svg.append("g")
      .attr("transform", `translate(0,${chartHeight})`)
      .call(d3.axisBottom(xScale).ticks(6))
      .selectAll("text")
      .style("fill", "var(--color-text-primary)")

    svg.append("g")
      .call(d3.axisLeft(yScale).ticks(6).tickFormat(d => this.formatCurrency(d)))
      .selectAll("text")
      .style("fill", "var(--color-text-primary)")

    // Line generator
    const line = d3.line()
      .x(d => xScale(d.date))
      .y(d => yScale(d.value))

    // Draw lines for each scenario
    selectedScenarios.forEach(scenarioName => {
      const scenarioData = allValues.filter(d => d.scenario === scenarioName)

      svg.append("path")
        .datum(scenarioData)
        .attr("fill", "none")
        .attr("stroke", this.chartConfig.colors[scenarioName])
        .attr("stroke-width", 2)
        .attr("stroke-dasharray", "5,5")
        .attr("d", line)
    })

    // Add vertical line at current date
    svg.append("line")
      .attr("x1", xScale(currentDate))
      .attr("x2", xScale(currentDate))
      .attr("y1", 0)
      .attr("y2", chartHeight)
      .attr("stroke", "var(--color-border-primary)")
      .attr("stroke-width", 2)
      .attr("stroke-dasharray", "3,3")

    // Add "Today" label
    svg.append("text")
      .attr("x", xScale(currentDate))
      .attr("y", -5)
      .attr("text-anchor", "middle")
      .attr("font-size", "12px")
      .attr("fill", "var(--color-text-subdued)")
      .text("Today")
  }

  renderMilestones() {
    const container = this.milestonesTarget
    const selectedScenarios = this.getSelectedScenarios()
    const timeframes = this.getSelectedTimeframes()

    // Clear existing
    container.innerHTML = ""

    if (!this.projectionData || selectedScenarios.length === 0) {
      return
    }

    // Show milestone for longest timeframe only
    const maxTimeframe = Math.max(...timeframes)

    selectedScenarios.forEach(scenarioName => {
      const scenario = this.projectionData.scenarios[scenarioName]
      const milestone = scenario.milestones[maxTimeframe]

      if (!milestone) return

      const card = document.createElement("div")
      card.className = "bg-gray-50 rounded-lg p-3"
      card.innerHTML = `
        <div class="text-xs font-medium text-subdued mb-1">
          ${this.formatScenarioName(scenarioName)} (${maxTimeframe}yr)
        </div>
        <div class="text-lg font-bold" style="color: ${this.chartConfig.colors[scenarioName]}">
          ${milestone.value.formatted}
        </div>
        <div class="text-xs text-subdued mt-1">
          ${milestone.growth_from_current.formatted} growth
        </div>
      `

      container.appendChild(card)
    })
  }

  formatCurrency(value) {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      minimumFractionDigits: 0,
      maximumFractionDigits: 0
    }).format(value)
  }

  formatScenarioName(scenario) {
    return scenario.charAt(0).toUpperCase() + scenario.slice(1)
  }

  showLoading() {
    this.loadingIndicatorTarget.classList.remove("hidden")
    this.chartContainerTarget.classList.add("hidden")
  }

  hideLoading() {
    this.loadingIndicatorTarget.classList.add("hidden")
    this.chartContainerTarget.classList.remove("hidden")
  }

  showInsufficientDataWarning() {
    this.insufficientDataWarningTarget.classList.remove("hidden")
    this.chartContainerTarget.classList.add("hidden")
  }

  showQualityWarning(message) {
    this.qualityWarningTextTarget.textContent = message
    this.qualityWarningTarget.classList.remove("hidden")
  }
}
```

### 6.2 Register Controller

- [ ] Ensure controller is registered in `app/javascript/controllers/index.js`

**Standard Pattern:**

```javascript
// app/javascript/controllers/index.js should auto-register
// Verify controller naming convention: net_worth_projection_controller.js
```

---

## Phase 7: Testing {#phase-7}

**Justification:** Ensures reliability of projection calculations, API endpoints, and user interface components.

### 7.1 Integration Tests

- [ ] Create `test/integration/net_worth_projection_test.rb`

**Standard Pattern:**

```ruby
# test/integration/net_worth_projection_test.rb
require "test_helper"

class NetWorthProjectionTest < ActionDispatch::IntegrationTest
  setup do
    @family = families(:dylan_family)
    @user = users(:family_admin)
    sign_in @user

    @account = accounts(:checking)

    # Create 12 months of balance history
    12.times do |i|
      Balance.create!(
        account: @account,
        date: Date.new(2023, i + 1, 1).end_of_month,
        balance: 10000 + (i * 500),
        end_balance: 10000 + (i * 500)
      )
    end
  end

  test "home page shows projection section when sufficient data" do
    get root_path
    assert_response :success
    assert_select "[data-controller='net-worth-projection']"
  end

  test "projection endpoint returns valid JSON" do
    get net_worth_projections_path(format: :json)
    assert_response :success

    json = JSON.parse(response.body)
    assert json["scenarios"]["realistic"]["milestones"].present?
  end

  test "projection respects selected timeframes" do
    get net_worth_projections_path(timeframes: "1,20", format: :json)
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal [1, 20], json["timeframes"]
  end

  test "end-to-end projection flow" do
    # Visit home page
    get root_path
    assert_response :success

    # Fetch projections
    get net_worth_projections_path(timeframes: "5,10", format: :json)
    assert_response :success

    json = JSON.parse(response.body)

    # Verify structure
    assert json["current_net_worth"].present?
    assert json["growth_rate"].present?
    assert json["scenarios"]["conservative"].present?
    assert json["scenarios"]["realistic"].present?
    assert json["scenarios"]["optimistic"].present?

    # Verify milestone data
    realistic = json["scenarios"]["realistic"]
    assert realistic["milestones"]["5"].present?
    assert realistic["milestones"]["10"].present?
  end
end
```

### 7.2 System Tests (Optional)

- [ ] Create `test/system/net_worth_projection_test.rb` (only if interactive testing needed)

**Standard Pattern:**

```ruby
# test/system/net_worth_projection_test.rb
require "application_system_test_case"

class NetWorthProjectionTest < ApplicationSystemTestCase
  setup do
    @user = users(:family_admin)
    @account = accounts(:checking)

    # Create historical data
    12.times do |i|
      Balance.create!(
        account: @account,
        date: Date.new(2023, i + 1, 1).end_of_month,
        balance: 10000 + (i * 500),
        end_balance: 10000 + (i * 500)
      )
    end

    sign_in @user
  end

  test "expanding projection section loads chart" do
    visit root_path

    # Find and click projection toggle
    within "[data-controller='net-worth-projection']" do
      click_button class: "[data-action='click->net-worth-projection#toggleExpanded']"

      # Wait for chart to load
      assert_selector "[data-net-worth-projection-target='chartContainer'] svg", wait: 5
    end
  end

  test "changing timeframes updates display" do
    visit root_path

    within "[data-controller='net-worth-projection']" do
      click_button class: "[data-action='click->net-worth-projection#toggleExpanded']"

      # Toggle 20 year timeframe
      check "20"

      # Wait for update
      assert_selector "[data-net-worth-projection-target='milestones']", wait: 5
    end
  end
end
```

---

## Phase 8: i18n and Documentation {#phase-8}

**Justification:** Ensures feature is properly internationalized and documented for users and maintainers.

### 8.1 Add i18n Translations

- [ ] Add translations to `config/locales/en.yml`

```yaml
en:
  net_worth:
    current_title: "Net Worth"
    projections:
      title: "Future Projections"
      insufficient_data: "At least 6 months of transaction history required for projections."
      select_timeframes: "Show projections for:"
      scenarios: "Scenarios"
      scenario_conservative: "Conservative (70%)"
      scenario_realistic: "Realistic (100%)"
      scenario_optimistic: "Optimistic (130%)"
      timeframe_years:
        one: "%{count} year"
        other: "%{count} years"
      growth_rate:
        label: "Historical growth rate"
        monthly: "Per month"
        annual: "Per year"
      data_quality:
        volatility:
          low: "Stable growth pattern"
          medium: "Moderate volatility"
          high: "High volatility - projections are estimates"
```

### 8.2 Update CHANGELOG

- [ ] Add entry to `CHANGELOG.md`

```markdown
## [Unreleased]

### Added
- Net Worth Projections: Calculate and visualize future net worth based on historical wealth accumulation
  - Analyzes minimum 6 months of transaction history to determine growth rate
  - Projects future net worth for user-selected timeframes (1, 2, 3, 5, 10, 20 years)
  - Displays three scenarios: conservative (70%), realistic (100%), optimistic (130%)
  - Integrated into Home page Net Worth card as expandable section
  - Interactive D3.js chart with dashed projection lines and milestone display
  - Data quality warnings for high volatility or insufficient history
```

### 8.3 Add Feature Documentation

- [ ] Create user documentation (if docs/ directory exists)

**Standard Pattern:**

Document the following:
- **What it does**: Projects future net worth based on historical wealth growth patterns
- **Requirements**: Minimum 6 months of transaction history
- **How to use**:
  - Navigate to Home page
  - Expand "Future Projections" section in Net Worth card
  - Select desired timeframes (1-20 years)
  - Toggle scenarios (conservative, realistic, optimistic)
- **Interpreting results**:
  - Dashed lines indicate projected values (not guaranteed)
  - Conservative scenario uses 70% of historical growth rate
  - Realistic scenario uses 100% of historical growth rate
  - Optimistic scenario uses 130% of historical growth rate
  - Data quality warnings indicate projection reliability
- **Limitations**:
  - Linear growth model (doesn't account for compounding or market changes)
  - Based on past performance (not guarantee of future results)
  - Most accurate for stable, consistent wealth accumulation patterns

---

## Validation Steps

After implementing all phases, verify:

- [ ] Home page displays Net Worth card with projection section
- [ ] Projection section is collapsible/expandable
- [ ] Insufficient data warning shows when < 6 months history
- [ ] All 6 timeframe options (1, 2, 3, 5, 10, 20 years) are selectable
- [ ] All 3 scenarios (conservative, realistic, optimistic) are toggleable
- [ ] Chart renders with dashed projection lines
- [ ] Chart distinguishes current date with vertical line
- [ ] Milestone cards show values for selected timeframes
- [ ] Data quality warnings display when present
- [ ] Changing timeframes triggers data reload
- [ ] Changing scenarios updates chart without reload
- [ ] Currency formatting matches family's currency
- [ ] All text is properly internationalized
- [ ] Run test suite: `bin/rails test`
- [ ] Run system tests: `bin/rails test:system` (if created)
- [ ] Verify no N+1 queries with Bullet gem
- [ ] Test with negative growth scenarios
- [ ] Test with volatile growth patterns
- [ ] Test with exactly 6 months of data
- [ ] Test with multi-currency accounts
