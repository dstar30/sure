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

      balance_sheet = BalanceSheet.new(family)

      # Generate monthly data points
      data_points = []
      current_date = start_date.end_of_month

      while current_date <= end_date
        value = calculate_net_worth_at_date(current_date)
        data_points << { date: current_date, value: value }
        current_date = (current_date + 1.month).end_of_month
      end

      data_points
    end

    # Calculate net worth at a specific date
    #
    # @param date [Date] The date to calculate for
    # @return [Money] Net worth at that date
    def calculate_net_worth_at_date(date)
      # Get all visible accounts
      accounts = family.accounts.visible

      total_assets = Money.new(0, family.currency)
      total_liabilities = Money.new(0, family.currency)

      accounts.each do |account|
        # Find most recent balance at or before the date
        balance_record = account.balances
          .where("date <= ?", date)
          .order(date: :desc)
          .first

        next unless balance_record

        balance_value = balance_record.balance
        balance_money = Money.new(balance_value, account.currency)

        # Convert to family currency if needed
        if account.currency != family.currency
          # Use simple conversion for now (exchange rate at date would be more accurate)
          balance_money = balance_money.exchange_to(family.currency)
        end

        if account.classification == "asset"
          total_assets += balance_money
        elsif account.classification == "liability"
          total_liabilities += balance_money
        end
      end

      total_assets - total_liabilities
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
