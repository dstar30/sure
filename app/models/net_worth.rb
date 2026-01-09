# Service class for net worth calculations and projections.
# Wraps BalanceSheet for current net worth and adds projection capabilities.
#
# @example Basic usage
#   net_worth = NetWorth.new(family)
#   current = net_worth.current
#   projections = net_worth.projections(timeframes: [1, 5, 10])
class NetWorth
  attr_reader :family

  def initialize(family)
    @family = family
  end

  # Get current net worth
  #
  # @return [Money] Current net worth (assets - liabilities)
  def current
    balance_sheet.net_worth
  end

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

  private

    def balance_sheet
      @balance_sheet ||= BalanceSheet.new(family)
    end
end
