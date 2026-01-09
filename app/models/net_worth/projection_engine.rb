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
    balance_sheet = BalanceSheet.new(family)
    current_value = balance_sheet.net_worth

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
      return { sufficient_data: true, monthly_rate: @monthly_growth_rate, monthly_rate_percent: 0.0, volatility: :low, warning: nil, data_points_used: 0, historical_period: {} } if @monthly_growth_rate

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
