# Retirement Planning Calculator - Implementation Plan

## Overview
A retirement planning calculator that projects future savings, estimates retirement needs, and shows whether current savings trajectory will meet retirement goals. Supports multiple scenarios (conservative, moderate, aggressive) and provides actionable insights.

**Key Components:**
- Backend: Retirement projection calculator with compound interest calculations
- Frontend: Interactive form with real-time projections and visualizations
- Scenarios: Multiple projection scenarios with different assumptions
- Integration: Leverages existing account balances as starting point

**Sequencing Logic:**
1. Backend calculation engine (retirement projections, scenarios)
2. Controller and routes
3. Frontend form and interactive calculator
4. Visualization with existing D3.js infrastructure
5. Testing and validation
6. i18n and documentation

---

## Table of Contents
1. [Phase 1: Backend - Retirement Projection Engine](#phase-1)
2. [Phase 2: Controller and Routes](#phase-2)
3. [Phase 3: Frontend - Calculator Interface](#phase-3)
4. [Phase 4: Visualization](#phase-4)
5. [Phase 5: Testing](#phase-5)
6. [Phase 6: i18n and Documentation](#phase-6)

---

## Phase 1: Backend - Retirement Projection Engine {#phase-1}

**Justification:** Core calculation logic for retirement projections. Follows "Skinny Controllers, Fat Models" convention by placing all financial logic in a dedicated service class.

### 1.1 Create Retirement Calculator Service

- [ ] Create `app/models/retirement_calculator.rb`

**Novel Implementation - Full Detail Required:**

```ruby
# app/models/retirement_calculator.rb

# Calculates retirement savings projections and determines retirement readiness
#
# Projects future savings growth based on current savings, contributions, and
# investment returns. Compares projections to estimated retirement needs.
#
# @example Basic usage
#   calculator = RetirementCalculator.new(
#     current_age: 35,
#     retirement_age: 65,
#     current_savings: 100000,
#     monthly_contribution: 1000,
#     annual_return_rate: 7.0,
#     retirement_expenses: 5000
#   )
#   projection = calculator.calculate
#
# @example With multiple scenarios
#   scenarios = calculator.calculate_scenarios
#   scenarios[:conservative] # 4% returns
#   scenarios[:moderate]     # 7% returns
#   scenarios[:aggressive]   # 10% returns
class RetirementCalculator
  attr_reader :current_age, :retirement_age, :current_savings, :monthly_contribution,
              :annual_return_rate, :retirement_expenses, :life_expectancy,
              :inflation_rate, :currency

  # Default assumptions
  DEFAULT_LIFE_EXPECTANCY = 90
  DEFAULT_INFLATION_RATE = 2.5
  DEFAULT_RETIREMENT_EXPENSES = 4000

  # Scenario presets
  SCENARIOS = {
    conservative: { return_rate: 4.0, inflation: 3.0 },
    moderate: { return_rate: 7.0, inflation: 2.5 },
    aggressive: { return_rate: 10.0, inflation: 2.0 }
  }.freeze

  # Initialize retirement calculator with parameters
  #
  # @param current_age [Integer] Current age in years
  # @param retirement_age [Integer] Desired retirement age
  # @param current_savings [Numeric] Current retirement savings amount
  # @param monthly_contribution [Numeric] Monthly contribution to retirement savings
  # @param annual_return_rate [Float] Expected annual return rate as percentage (e.g., 7.0 for 7%)
  # @param retirement_expenses [Numeric] Expected monthly expenses in retirement
  # @param life_expectancy [Integer] Expected life expectancy (default 90)
  # @param inflation_rate [Float] Expected annual inflation rate as percentage (default 2.5)
  # @param currency [String] Currency code (default "USD")
  def initialize(current_age:, retirement_age:, current_savings:, monthly_contribution:,
                 annual_return_rate:, retirement_expenses: DEFAULT_RETIREMENT_EXPENSES,
                 life_expectancy: DEFAULT_LIFE_EXPECTANCY, inflation_rate: DEFAULT_INFLATION_RATE,
                 currency: "USD")
    @current_age = current_age.to_i
    @retirement_age = retirement_age.to_i
    @current_savings = current_savings.to_f
    @monthly_contribution = monthly_contribution.to_f
    @annual_return_rate = annual_return_rate.to_f
    @retirement_expenses = retirement_expenses.to_f
    @life_expectancy = life_expectancy.to_i
    @inflation_rate = inflation_rate.to_f
    @currency = currency

    validate_inputs!
  end

  # Calculate complete retirement projection
  #
  # @return [Hash] Comprehensive projection data including trajectory, needs, and readiness
  #
  # @example Return structure
  #   {
  #     retirement_age: 65,
  #     years_until_retirement: 30,
  #     years_in_retirement: 25,
  #     projected_savings_at_retirement: Money,
  #     total_needed_at_retirement: Money,
  #     monthly_income_in_retirement: Money,
  #     is_on_track: true/false,
  #     gap: Money (negative if shortfall, positive if surplus),
  #     gap_percentage: Float,
  #     trajectory: [...], # Array of yearly projections
  #     recommendations: [...]
  #   }
  def calculate
    years_until_retirement = retirement_age - current_age
    years_in_retirement = life_expectancy - retirement_age

    # Calculate savings at retirement
    projected_savings = calculate_future_value(
      present_value: current_savings,
      monthly_contribution: monthly_contribution,
      annual_rate: annual_return_rate,
      years: years_until_retirement
    )

    # Calculate retirement needs
    retirement_needs = calculate_retirement_needs(
      monthly_expenses: retirement_expenses,
      years_in_retirement: years_in_retirement,
      inflation_rate: inflation_rate
    )

    # Calculate monthly income available in retirement (4% rule)
    monthly_income = (projected_savings * 0.04) / 12

    # Determine if on track
    gap = projected_savings - retirement_needs
    is_on_track = gap >= 0
    gap_percentage = retirement_needs > 0 ? (gap / retirement_needs * 100).round(2) : 0

    # Generate year-by-year trajectory
    trajectory = calculate_trajectory(years_until_retirement)

    # Generate recommendations
    recommendations = generate_recommendations(
      is_on_track: is_on_track,
      gap: gap,
      years_until_retirement: years_until_retirement
    )

    {
      current_age: current_age,
      retirement_age: retirement_age,
      years_until_retirement: years_until_retirement,
      years_in_retirement: years_in_retirement,
      current_savings: Money.new((current_savings * 100).to_i, currency),
      projected_savings_at_retirement: Money.new((projected_savings * 100).to_i, currency),
      total_needed_at_retirement: Money.new((retirement_needs * 100).to_i, currency),
      monthly_income_in_retirement: Money.new((monthly_income * 100).to_i, currency),
      is_on_track: is_on_track,
      gap: Money.new((gap * 100).to_i, currency),
      gap_percentage: gap_percentage,
      trajectory: trajectory,
      recommendations: recommendations
    }
  end

  # Calculate projections for multiple scenarios
  #
  # @return [Hash] Projections for conservative, moderate, and aggressive scenarios
  def calculate_scenarios
    SCENARIOS.map do |scenario_name, assumptions|
      calculator = self.class.new(
        current_age: current_age,
        retirement_age: retirement_age,
        current_savings: current_savings,
        monthly_contribution: monthly_contribution,
        annual_return_rate: assumptions[:return_rate],
        retirement_expenses: retirement_expenses,
        life_expectancy: life_expectancy,
        inflation_rate: assumptions[:inflation],
        currency: currency
      )

      [scenario_name, calculator.calculate]
    end.to_h
  end

  # Get scenario assumptions for display
  #
  # @return [Hash] Scenario assumptions
  def self.scenario_assumptions
    SCENARIOS
  end

  private

    # Validate input parameters
    #
    # @raise [ArgumentError] if inputs are invalid
    def validate_inputs!
      raise ArgumentError, "Current age must be positive" if current_age <= 0
      raise ArgumentError, "Retirement age must be greater than current age" if retirement_age <= current_age
      raise ArgumentError, "Current savings cannot be negative" if current_savings < 0
      raise ArgumentError, "Monthly contribution cannot be negative" if monthly_contribution < 0
      raise ArgumentError, "Life expectancy must be greater than retirement age" if life_expectancy <= retirement_age
    end

    # Calculate future value with monthly contributions
    #
    # Uses compound interest formula with regular monthly contributions:
    # FV = PV * (1 + r)^n + PMT * [((1 + r)^n - 1) / r]
    #
    # @param present_value [Float] Current savings amount
    # @param monthly_contribution [Float] Monthly contribution amount
    # @param annual_rate [Float] Annual return rate as percentage
    # @param years [Integer] Number of years to project
    # @return [Float] Future value
    def calculate_future_value(present_value:, monthly_contribution:, annual_rate:, years:)
      monthly_rate = (annual_rate / 100.0) / 12.0
      months = years * 12

      # Future value of current savings
      fv_savings = present_value * ((1 + monthly_rate)**months)

      # Future value of monthly contributions (annuity)
      if monthly_rate > 0
        fv_contributions = monthly_contribution * (((1 + monthly_rate)**months - 1) / monthly_rate)
      else
        fv_contributions = monthly_contribution * months
      end

      fv_savings + fv_contributions
    end

    # Calculate total retirement needs
    #
    # Estimates total savings needed at retirement to support desired
    # monthly expenses for the retirement period, accounting for inflation.
    #
    # Uses present value of annuity formula adjusted for inflation.
    #
    # @param monthly_expenses [Float] Desired monthly expenses in retirement
    # @param years_in_retirement [Integer] Expected years in retirement
    # @param inflation_rate [Float] Expected inflation rate as percentage
    # @return [Float] Total amount needed at retirement
    def calculate_retirement_needs(monthly_expenses:, years_in_retirement:, inflation_rate:)
      # Using simplified approach: total expenses needed assuming 4% withdrawal rate
      # and adjusting for inflation
      annual_expenses = monthly_expenses * 12

      # Adjust first year expenses for inflation from now to retirement
      years_until_retirement = retirement_age - current_age
      inflation_multiplier = (1 + inflation_rate / 100.0)**years_until_retirement
      adjusted_annual_expenses = annual_expenses * inflation_multiplier

      # Calculate total needed using 4% rule (25x annual expenses)
      adjusted_annual_expenses * 25
    end

    # Generate year-by-year savings trajectory
    #
    # @param years [Integer] Number of years to project
    # @return [Array<Hash>] Array of yearly projections
    def calculate_trajectory(years)
      trajectory = []
      balance = current_savings

      (0..years).each do |year|
        age = current_age + year

        trajectory << {
          year: year,
          age: age,
          balance: Money.new((balance * 100).to_i, currency),
          total_contributed: Money.new((current_savings + (monthly_contribution * 12 * year)) * 100, currency)
        }

        # Calculate next year's balance
        annual_contribution = monthly_contribution * 12
        balance = balance * (1 + annual_return_rate / 100.0) + annual_contribution
      end

      trajectory
    end

    # Generate personalized recommendations
    #
    # @param is_on_track [Boolean] Whether user is on track for retirement
    # @param gap [Float] Shortfall or surplus amount
    # @param years_until_retirement [Integer] Years until retirement
    # @return [Array<String>] Array of recommendations
    def generate_recommendations(is_on_track:, gap:, years_until_retirement:)
      recommendations = []

      if is_on_track
        recommendations << "You're on track to meet your retirement goals! Keep up your current savings rate."

        if gap > 0
          surplus_percentage = (gap / current_savings * 100).round(0)
          recommendations << "You're projected to have a surplus of #{Money.new((gap * 100).to_i, currency).format}. Consider increasing your lifestyle goals or retiring earlier."
        end
      else
        shortfall = gap.abs

        # Calculate additional monthly contribution needed to close gap
        additional_monthly = calculate_additional_contribution_needed(shortfall, years_until_retirement)

        recommendations << "You have a projected shortfall of #{Money.new((shortfall * 100).to_i, currency).format}."
        recommendations << "Consider increasing your monthly contribution by #{Money.new((additional_monthly * 100).to_i, currency).format} to close the gap."

        # Alternative recommendations
        years_to_add = calculate_years_to_add_for_goal(shortfall)
        if years_to_add > 0 && (retirement_age + years_to_add) < life_expectancy
          recommendations << "Alternatively, consider working #{years_to_add} additional years to reach your goal."
        end

        recommendations << "Review your investment allocation to potentially increase your return rate within your risk tolerance."
      end

      recommendations
    end

    # Calculate additional monthly contribution needed to close shortfall
    #
    # @param shortfall [Float] Amount short of goal
    # @param years [Integer] Years until retirement
    # @return [Float] Additional monthly contribution needed
    def calculate_additional_contribution_needed(shortfall, years)
      return 0 if years <= 0

      monthly_rate = (annual_return_rate / 100.0) / 12.0
      months = years * 12

      # Solve for PMT in future value of annuity formula
      if monthly_rate > 0
        shortfall / (((1 + monthly_rate)**months - 1) / monthly_rate)
      else
        shortfall / months
      end
    end

    # Calculate additional years needed to reach goal
    #
    # @param shortfall [Float] Amount short of goal
    # @return [Integer] Additional years to work
    def calculate_years_to_add_for_goal(shortfall)
      # Simplified: calculate how many more years of contributions at current rate
      # would be needed to make up the shortfall
      annual_contribution = monthly_contribution * 12
      return 0 if annual_contribution <= 0

      years_needed = (shortfall / annual_contribution).ceil
      [years_needed, 10].min # Cap at 10 years for practicality
    end
end
```

### 1.2 Add Retirement Calculator Model for Persistence

- [ ] Generate migration for RetirementPlan model
- [ ] Create `app/models/retirement_plan.rb`

**Novel Model - Full Detail:**

```ruby
# app/models/retirement_plan.rb

# Persisted retirement plan for tracking assumptions and comparing scenarios over time
#
# Allows users to save their retirement plan parameters and revisit projections
# as their financial situation changes.
class RetirementPlan < ApplicationRecord
  belongs_to :family

  validates :name, presence: true
  validates :current_age, :retirement_age, :current_savings,
            :monthly_contribution, :annual_return_rate,
            numericality: { greater_than_or_equal_to: 0 }

  # Calculate projections for this plan
  #
  # @return [Hash] Projection results from RetirementCalculator
  def calculate
    calculator = RetirementCalculator.new(
      current_age: current_age,
      retirement_age: retirement_age,
      current_savings: current_savings,
      monthly_contribution: monthly_contribution,
      annual_return_rate: annual_return_rate,
      retirement_expenses: retirement_expenses,
      life_expectancy: life_expectancy || RetirementCalculator::DEFAULT_LIFE_EXPECTANCY,
      inflation_rate: inflation_rate || RetirementCalculator::DEFAULT_INFLATION_RATE,
      currency: family.currency
    )

    calculator.calculate
  end

  # Calculate scenarios for this plan
  #
  # @return [Hash] Scenario projections
  def calculate_scenarios
    calculator = RetirementCalculator.new(
      current_age: current_age,
      retirement_age: retirement_age,
      current_savings: current_savings,
      monthly_contribution: monthly_contribution,
      annual_return_rate: annual_return_rate,
      retirement_expenses: retirement_expenses,
      life_expectancy: life_expectancy || RetirementCalculator::DEFAULT_LIFE_EXPECTANCY,
      inflation_rate: inflation_rate || RetirementCalculator::DEFAULT_INFLATION_RATE,
      currency: family.currency
    )

    calculator.calculate_scenarios
  end

  # Initialize plan with current family financial data
  #
  # @param family [Family] The family to create plan for
  # @return [RetirementPlan] Initialized plan
  def self.initialize_with_family_data(family)
    # Calculate current retirement savings (sum of investment accounts)
    retirement_accounts = family.accounts.visible.where(accountable_type: "Investment")
    current_retirement_savings = retirement_accounts.sum(:balance)

    new(
      family: family,
      name: "My Retirement Plan",
      current_age: 35, # Will need to be set by user
      retirement_age: 65,
      current_savings: current_retirement_savings,
      monthly_contribution: 0, # User needs to input
      annual_return_rate: 7.0,
      retirement_expenses: 4000,
      life_expectancy: 90,
      inflation_rate: 2.5
    )
  end
end
```

- [ ] Generate migration:

```ruby
class CreateRetirementPlans < ActiveRecord::Migration[7.0]
  def change
    create_table :retirement_plans do |t|
      t.references :family, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :current_age, null: false
      t.integer :retirement_age, null: false
      t.decimal :current_savings, precision: 19, scale: 4, default: 0
      t.decimal :monthly_contribution, precision: 19, scale: 4, default: 0
      t.decimal :annual_return_rate, precision: 5, scale: 2, default: 7.0
      t.decimal :retirement_expenses, precision: 19, scale: 4
      t.integer :life_expectancy, default: 90
      t.decimal :inflation_rate, precision: 5, scale: 2, default: 2.5
      t.text :notes

      t.timestamps
    end

    add_index :retirement_plans, [:family_id, :created_at]
  end
end
```

### 1.3 Add Tests

- [ ] Create `test/models/retirement_calculator_test.rb`

**Novel Testing - Full Detail:**

```ruby
# test/models/retirement_calculator_test.rb
require "test_helper"

class RetirementCalculatorTest < ActiveSupport::TestCase
  test "calculates future value with monthly contributions" do
    calculator = RetirementCalculator.new(
      current_age: 35,
      retirement_age: 65,
      current_savings: 100000,
      monthly_contribution: 1000,
      annual_return_rate: 7.0,
      retirement_expenses: 5000
    )

    projection = calculator.calculate

    assert projection[:projected_savings_at_retirement] > Money.new(100000 * 100, "USD")
    assert_equal 30, projection[:years_until_retirement]
    assert_equal 25, projection[:years_in_retirement]
  end

  test "determines if on track for retirement" do
    # Generous savings scenario
    on_track_calculator = RetirementCalculator.new(
      current_age: 35,
      retirement_age: 65,
      current_savings: 500000,
      monthly_contribution: 2000,
      annual_return_rate: 7.0,
      retirement_expenses: 3000
    )

    projection = on_track_calculator.calculate
    assert projection[:is_on_track], "Should be on track with generous savings"
    assert projection[:gap] > Money.new(0, "USD")
  end

  test "generates recommendations for shortfall" do
    calculator = RetirementCalculator.new(
      current_age: 45,
      retirement_age: 65,
      current_savings: 50000,
      monthly_contribution: 500,
      annual_return_rate: 7.0,
      retirement_expenses: 6000
    )

    projection = calculator.calculate

    refute projection[:is_on_track]
    assert projection[:recommendations].any? { |r| r.include?("shortfall") }
    assert projection[:recommendations].any? { |r| r.include?("increasing your monthly contribution") }
  end

  test "calculates multiple scenarios" do
    calculator = RetirementCalculator.new(
      current_age: 35,
      retirement_age: 65,
      current_savings: 100000,
      monthly_contribution: 1000,
      annual_return_rate: 7.0,
      retirement_expenses: 5000
    )

    scenarios = calculator.calculate_scenarios

    assert_includes scenarios.keys, :conservative
    assert_includes scenarios.keys, :moderate
    assert_includes scenarios.keys, :aggressive

    # Aggressive should have higher projected savings
    assert scenarios[:aggressive][:projected_savings_at_retirement] >
           scenarios[:conservative][:projected_savings_at_retirement]
  end

  test "generates year-by-year trajectory" do
    calculator = RetirementCalculator.new(
      current_age: 35,
      retirement_age: 40, # Short period for testing
      current_savings: 50000,
      monthly_contribution: 1000,
      annual_return_rate: 7.0,
      retirement_expenses: 3000
    )

    projection = calculator.calculate
    trajectory = projection[:trajectory]

    assert_equal 6, trajectory.length # 0 to 5 years = 6 data points
    assert_equal 35, trajectory.first[:age]
    assert_equal 40, trajectory.last[:age]

    # Balance should grow each year
    assert trajectory.last[:balance] > trajectory.first[:balance]
  end

  test "raises error for invalid inputs" do
    assert_raises(ArgumentError) do
      RetirementCalculator.new(
        current_age: 65,
        retirement_age: 60, # Invalid: retirement age before current age
        current_savings: 100000,
        monthly_contribution: 1000,
        annual_return_rate: 7.0,
        retirement_expenses: 5000
      )
    end
  end
end
```

- [ ] Create `test/models/retirement_plan_test.rb`

**Standard Pattern:**

Follow existing model test patterns for associations and validations.

---

## Phase 2: Controller and Routes {#phase-2}

**Justification:** Exposes retirement calculator via RESTful resources following Rails conventions.

### 2.1 Create Retirement Plans Controller

- [ ] Create `app/controllers/retirement_plans_controller.rb`

**Standard Pattern - Reference Existing:**

Follow the CRUD pattern from other resource controllers (e.g., `budgets_controller.rb`):

```ruby
# app/controllers/retirement_plans_controller.rb
class RetirementPlansController < ApplicationController
  before_action :set_retirement_plan, only: [:show, :edit, :update, :destroy]

  def index
    @retirement_plans = Current.family.retirement_plans.order(created_at: :desc)
  end

  def show
    @projection = @retirement_plan.calculate
    @scenarios = @retirement_plan.calculate_scenarios
  end

  def new
    @retirement_plan = Current.family.retirement_plans.initialize_with_family_data(Current.family)
  end

  def create
    @retirement_plan = Current.family.retirement_plans.new(retirement_plan_params)

    if @retirement_plan.save
      redirect_to @retirement_plan, notice: "Retirement plan created successfully"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @retirement_plan.update(retirement_plan_params)
      redirect_to @retirement_plan, notice: "Retirement plan updated successfully"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @retirement_plan.destroy
    redirect_to retirement_plans_path, notice: "Retirement plan deleted"
  end

  # Quick calculator without saving
  def calculate
    @calculator = RetirementCalculator.new(calculator_params)
    @projection = @calculator.calculate
    @scenarios = @calculator.calculate_scenarios

    respond_to do |format|
      format.turbo_stream
      format.html { render :quick_calculator }
    end
  end

  private

    def set_retirement_plan
      @retirement_plan = Current.family.retirement_plans.find(params[:id])
    end

    def retirement_plan_params
      params.require(:retirement_plan).permit(
        :name, :current_age, :retirement_age, :current_savings,
        :monthly_contribution, :annual_return_rate, :retirement_expenses,
        :life_expectancy, :inflation_rate, :notes
      )
    end

    def calculator_params
      params.permit(
        :current_age, :retirement_age, :current_savings,
        :monthly_contribution, :annual_return_rate, :retirement_expenses,
        :life_expectancy, :inflation_rate
      ).merge(currency: Current.family.currency)
    end
end
```

### 2.2 Add Routes

- [ ] Add routes in `config/routes.rb`

```ruby
resources :retirement_plans do
  collection do
    post :calculate # Quick calculator without persistence
  end
end
```

---

## Phase 3: Frontend - Calculator Interface {#phase-3}

**Justification:** User-facing interface for inputting retirement parameters and viewing projections. Uses Hotwire for reactive updates.

### 3.1 Create Calculator Form

- [ ] Create `app/views/retirement_plans/new.html.erb`
- [ ] Create `app/views/retirement_plans/_form.html.erb`

**Standard Pattern - Reference Existing Forms:**

Follow form patterns from existing resources (budgets, accounts):
- Use Tailwind design system tokens
- Form fields with labels using i18n
- Real-time validation
- Helper text explaining each field

```erb
<%# app/views/retirement_plans/_form.html.erb %>
<%= form_with(model: retirement_plan, class: "space-y-6", data: { controller: "retirement-calculator" }) do |form| %>
  <%# Basic Information %>
  <div class="bg-container border border-primary rounded-lg p-6">
    <h3 class="text-lg font-semibold text-primary mb-4"><%= t("retirement_plans.form.basic_info") %></h3>

    <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
      <div>
        <%= form.label :name, class: "block text-sm font-medium text-primary mb-1" %>
        <%= form.text_field :name, class: "w-full px-3 py-2 border border-primary rounded-lg" %>
      </div>

      <div>
        <%= form.label :current_age, class: "block text-sm font-medium text-primary mb-1" %>
        <%= form.number_field :current_age,
            class: "w-full px-3 py-2 border border-primary rounded-lg",
            data: { action: "change->retirement-calculator#recalculate" } %>
        <p class="text-xs text-subdued mt-1"><%= t("retirement_plans.form.current_age_help") %></p>
      </div>

      <div>
        <%= form.label :retirement_age, class: "block text-sm font-medium text-primary mb-1" %>
        <%= form.number_field :retirement_age,
            class: "w-full px-3 py-2 border border-primary rounded-lg",
            data: { action: "change->retirement-calculator#recalculate" } %>
      </div>
    </div>
  </div>

  <%# Current Savings %>
  <div class="bg-container border border-primary rounded-lg p-6">
    <h3 class="text-lg font-semibold text-primary mb-4"><%= t("retirement_plans.form.savings") %></h3>

    <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
      <div>
        <%= form.label :current_savings, class: "block text-sm font-medium text-primary mb-1" %>
        <%= form.number_field :current_savings,
            step: 0.01,
            class: "w-full px-3 py-2 border border-primary rounded-lg",
            data: {
              controller: "money-field",
              action: "change->retirement-calculator#recalculate"
            } %>
        <p class="text-xs text-subdued mt-1"><%= t("retirement_plans.form.current_savings_help") %></p>
      </div>

      <div>
        <%= form.label :monthly_contribution, class: "block text-sm font-medium text-primary mb-1" %>
        <%= form.number_field :monthly_contribution,
            step: 0.01,
            class: "w-full px-3 py-2 border border-primary rounded-lg",
            data: {
              controller: "money-field",
              action: "change->retirement-calculator#recalculate"
            } %>
      </div>
    </div>
  </div>

  <%# Investment Assumptions %>
  <div class="bg-container border border-primary rounded-lg p-6">
    <h3 class="text-lg font-semibold text-primary mb-4"><%= t("retirement_plans.form.assumptions") %></h3>

    <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
      <div>
        <%= form.label :annual_return_rate, class: "block text-sm font-medium text-primary mb-1" %>
        <%= form.number_field :annual_return_rate,
            step: 0.1,
            class: "w-full px-3 py-2 border border-primary rounded-lg",
            data: { action: "change->retirement-calculator#recalculate" } %>
        <p class="text-xs text-subdued mt-1">7% is typical for balanced portfolio</p>
      </div>

      <div>
        <%= form.label :inflation_rate, class: "block text-sm font-medium text-primary mb-1" %>
        <%= form.number_field :inflation_rate,
            step: 0.1,
            value: form.object.inflation_rate || 2.5,
            class: "w-full px-3 py-2 border border-primary rounded-lg",
            data: { action: "change->retirement-calculator#recalculate" } %>
      </div>

      <div>
        <%= form.label :life_expectancy, class: "block text-sm font-medium text-primary mb-1" %>
        <%= form.number_field :life_expectancy,
            value: form.object.life_expectancy || 90,
            class: "w-full px-3 py-2 border border-primary rounded-lg",
            data: { action: "change->retirement-calculator#recalculate" } %>
      </div>
    </div>
  </div>

  <%# Retirement Expenses %>
  <div class="bg-container border border-primary rounded-lg p-6">
    <h3 class="text-lg font-semibold text-primary mb-4"><%= t("retirement_plans.form.expenses") %></h3>

    <div>
      <%= form.label :retirement_expenses, class: "block text-sm font-medium text-primary mb-1" %>
      <%= form.number_field :retirement_expenses,
          step: 0.01,
          class: "w-full px-3 py-2 border border-primary rounded-lg",
          data: {
            controller: "money-field",
            action: "change->retirement-calculator#recalculate"
          } %>
      <p class="text-xs text-subdued mt-1"><%= t("retirement_plans.form.retirement_expenses_help") %></p>
    </div>
  </div>

  <%# Actions %>
  <div class="flex justify-end gap-4">
    <%= link_to t("common.cancel"), retirement_plans_path, class: "px-4 py-2 text-subdued hover:text-primary" %>
    <%= form.submit t("common.save"), class: "px-4 py-2 bg-primary text-white rounded-lg hover:bg-primary/90" %>
  </div>
<% end %>
```

### 3.2 Create Stimulus Controller for Real-time Updates

- [ ] Create `app/javascript/controllers/retirement_calculator_controller.js`

**Novel Controller - Full Detail:**

```javascript
// app/javascript/controllers/retirement_calculator_controller.js
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["projectionResult"];
  static values = {
    calculateUrl: String,
  };

  connect() {
    this.timeout = null;
  }

  // Recalculate when inputs change
  recalculate() {
    // Debounce recalculation
    clearTimeout(this.timeout);
    this.timeout = setTimeout(() => {
      this.performCalculation();
    }, 500);
  }

  async performCalculation() {
    const formData = new FormData(this.element);
    const params = new URLSearchParams(formData);

    try {
      const response = await fetch(
        `${this.calculateUrlValue}?${params.toString()}`,
        {
          headers: {
            Accept: "text/vnd.turbo-stream.html",
          },
        }
      );

      if (response.ok) {
        const html = await response.text();
        Turbo.renderStreamMessage(html);
      }
    } catch (error) {
      console.error("Calculation failed:", error);
    }
  }
}
```

### 3.3 Create Results Display

- [ ] Create `app/views/retirement_plans/show.html.erb`

**Standard Pattern:**

Display projection results with:
- Summary cards (on track status, projected savings, gap)
- Scenario comparison
- Recommendations list
- Year-by-year trajectory chart

---

## Phase 4: Visualization {#phase-4}

**Justification:** Visual representation of retirement projections helps users understand their trajectory.

### 4.1 Add Chart for Savings Trajectory

- [ ] Reuse `time_series_chart_controller.js` for trajectory visualization
- [ ] Add helper method for formatting chart data

**Standard Pattern - Reference Existing:**

Follow the same pattern used in net worth timeline:
- Format data for time_series_chart controller
- Multiple lines for different scenarios
- Annotations for retirement age milestone

---

## Phase 5: Testing {#phase-5}

**Justification:** Ensures calculator accuracy and UI functionality.

### 5.1 Controller Tests

- [ ] Add tests in `test/controllers/retirement_plans_controller_test.rb`

**Standard Pattern:**

Test CRUD operations and calculator endpoint.

### 5.2 System Tests (Optional)

- [ ] Test complete user flow of creating retirement plan

---

## Phase 6: i18n and Documentation {#phase-6}

**Justification:** Internationalization and user documentation.

### 6.1 Add Translations

- [ ] Add to `config/locales/en.yml`

```yaml
en:
  retirement_plans:
    index:
      title: "Retirement Planning"
      new_plan: "New Plan"
    form:
      basic_info: "Basic Information"
      savings: "Current Savings"
      assumptions: "Investment Assumptions"
      expenses: "Retirement Expenses"
      current_age_help: "Your current age in years"
      current_savings_help: "Total retirement savings across all accounts"
      retirement_expenses_help: "Expected monthly expenses in retirement"
    show:
      on_track: "You're on track!"
      shortfall: "Projected shortfall"
      scenarios: "Scenario Comparison"
      recommendations: "Recommendations"
```

### 6.2 Update Documentation

- [ ] Add entry to `CHANGELOG.md`
- [ ] Create user guide for retirement planning feature

---

## Validation Steps

After implementation:

- [ ] Create new retirement plan with sample data
- [ ] Verify calculations are accurate
- [ ] Test scenario comparisons
- [ ] Verify chart displays correctly
- [ ] Test form validation
- [ ] Test real-time recalculation
- [ ] Verify recommendations are helpful
- [ ] Test with edge cases (very young, near retirement)
- [ ] Run full test suite
