class PagesController < ApplicationController
  include Periodable

  skip_authentication only: :redis_configuration_error

  def dashboard
    @balance_sheet = Current.family.balance_sheet
    @accounts = Current.family.accounts.visible.with_attached_logo

    family_currency = Current.family.currency

    # Use the same period for all widgets (set by Periodable concern)
    income_totals = Current.family.income_statement.income_totals(period: @period)
    expense_totals = Current.family.income_statement.expense_totals(period: @period)

    @cashflow_sankey_data = build_cashflow_sankey_data(income_totals, expense_totals, family_currency)
    @outflows_data = build_outflows_donut_data(expense_totals, family_currency)

    @dashboard_sections = build_dashboard_sections

    @breadcrumbs = [ [ "Home", root_path ], [ "Dashboard", nil ] ]
  end

  def update_preferences
    if Current.user.update_dashboard_preferences(preferences_params)
      head :ok
    else
      head :unprocessable_entity
    end
  end

  def changelog
    @release_notes = github_provider.fetch_latest_release_notes

    # Fallback if no release notes are available
    if @release_notes.nil?
      @release_notes = {
        avatar: "https://github.com/we-promise.png",
        username: "we-promise",
        name: "Release notes unavailable",
        published_at: Date.current,
        body: "<p>Unable to fetch the latest release notes at this time. Please check back later or visit our <a href='https://github.com/we-promise/sure/releases' target='_blank'>GitHub releases page</a> directly.</p>"
      }
    end

    render layout: "settings"
  end

  def feedback
    render layout: "settings"
  end

  def redis_configuration_error
    render layout: "blank"
  end

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
    def preferences_params
      prefs = params.require(:preferences)
      {}.tap do |permitted|
        permitted["collapsed_sections"] = prefs[:collapsed_sections].to_unsafe_h if prefs[:collapsed_sections]
        permitted["section_order"] = prefs[:section_order] if prefs[:section_order]
      end
    end

    def build_dashboard_sections
      all_sections = [
        {
          key: "cashflow_sankey",
          title: "pages.dashboard.cashflow_sankey.title",
          partial: "pages/dashboard/cashflow_sankey",
          locals: { sankey_data: @cashflow_sankey_data, period: @period },
          visible: Current.family.accounts.any?,
          collapsible: true
        },
        {
          key: "outflows_donut",
          title: "pages.dashboard.outflows_donut.title",
          partial: "pages/dashboard/outflows_donut",
          locals: { outflows_data: @outflows_data, period: @period },
          visible: Current.family.accounts.any? && @outflows_data[:categories].present?,
          collapsible: true
        },
        {
          key: "net_worth_chart",
          title: "pages.dashboard.net_worth_chart.title",
          partial: "pages/dashboard/net_worth_chart",
          locals: { balance_sheet: @balance_sheet, period: @period },
          visible: Current.family.accounts.any?,
          collapsible: true
        },
        {
          key: "balance_sheet",
          title: "pages.dashboard.balance_sheet.title",
          partial: "pages/dashboard/balance_sheet",
          locals: { balance_sheet: @balance_sheet },
          visible: Current.family.accounts.any?,
          collapsible: true
        }
      ]

      # Order sections according to user preference
      section_order = Current.user.dashboard_section_order
      ordered_sections = section_order.map do |key|
        all_sections.find { |s| s[:key] == key }
      end.compact

      # Add any new sections that aren't in the saved order (future-proofing)
      all_sections.each do |section|
        ordered_sections << section unless ordered_sections.include?(section)
      end

      ordered_sections
    end

    def github_provider
      Provider::Registry.get_provider(:github)
    end

    def build_cashflow_sankey_data(income_totals, expense_totals, currency_symbol)
      nodes = []
      links = []
      node_indices = {} # Memoize node indices by a unique key: "type_categoryid"

      # Helper to add/find node and return its index
      add_node = ->(unique_key, display_name, value, percentage, color) {
        node_indices[unique_key] ||= begin
          nodes << { name: display_name, value: value.to_f.round(2), percentage: percentage.to_f.round(1), color: color }
          nodes.size - 1
        end
      }

      total_income_val = income_totals.total.to_f.round(2)
      total_expense_val = expense_totals.total.to_f.round(2)

      # --- Create Central Cash Flow Node ---
      cash_flow_idx = add_node.call("cash_flow_node", "Cash Flow", total_income_val, 0, "var(--color-success)")

      # --- Process Income Side (Top-level categories only) ---
      income_totals.category_totals.each do |ct|
        # Skip subcategories – only include root income categories
        next if ct.category.parent_id.present?

        val = ct.total.to_f.round(2)
        next if val.zero?

        percentage_of_total_income = total_income_val.zero? ? 0 : (val / total_income_val * 100).round(1)

        node_display_name = ct.category.name
        node_color = ct.category.color.presence || Category::COLORS.sample

        current_cat_idx = add_node.call(
          "income_#{ct.category.id}",
          node_display_name,
          val,
          percentage_of_total_income,
          node_color
        )

        links << {
          source: current_cat_idx,
          target: cash_flow_idx,
          value: val,
          color: node_color,
          percentage: percentage_of_total_income
        }
      end

      # --- Process Expense Side (Top-level categories only) ---
      expense_totals.category_totals.each do |ct|
        # Skip subcategories – only include root expense categories to keep Sankey shallow
        next if ct.category.parent_id.present?

        val = ct.total.to_f.round(2)
        next if val.zero?

        percentage_of_total_expense = total_expense_val.zero? ? 0 : (val / total_expense_val * 100).round(1)

        node_display_name = ct.category.name
        node_color = ct.category.color.presence || Category::UNCATEGORIZED_COLOR

        current_cat_idx = add_node.call(
          "expense_#{ct.category.id}",
          node_display_name,
          val,
          percentage_of_total_expense,
          node_color
        )

        links << {
          source: cash_flow_idx,
          target: current_cat_idx,
          value: val,
          color: node_color,
          percentage: percentage_of_total_expense
        }
      end

      # --- Process Surplus ---
      leftover = (total_income_val - total_expense_val).round(2)
      if leftover.positive?
        percentage_of_total_income_for_surplus = total_income_val.zero? ? 0 : (leftover / total_income_val * 100).round(1)
        surplus_idx = add_node.call("surplus_node", "Surplus", leftover, percentage_of_total_income_for_surplus, "var(--color-success)")
        links << { source: cash_flow_idx, target: surplus_idx, value: leftover, color: "var(--color-success)", percentage: percentage_of_total_income_for_surplus }
      end

      # Update Cash Flow and Income node percentages (relative to total income)
      if node_indices["cash_flow_node"]
        nodes[node_indices["cash_flow_node"]][:percentage] = 100.0
      end
      # No primary income node anymore, percentages are on individual income cats relative to total_income_val

      { nodes: nodes, links: links, currency_symbol: Money::Currency.new(currency_symbol).symbol }
    end

    def build_outflows_donut_data(expense_totals, family_currency)
      total = expense_totals.total

      # Only include top-level categories with non-zero amounts
      categories = expense_totals.category_totals
        .reject { |ct| ct.category.parent_id.present? || ct.total.zero? }
        .sort_by { |ct| -ct.total }
        .map do |ct|
          {
            id: ct.category.id,
            name: ct.category.name,
            amount: ct.total.to_f.round(2),
            currency: ct.currency,
            percentage: ct.weight.round(1),
            color: ct.category.color.presence || Category::UNCATEGORIZED_COLOR,
            icon: ct.category.lucide_icon
          }
        end

      { categories: categories, total: total.to_f.round(2), currency: family_currency, currency_symbol: Money::Currency.new(family_currency).symbol }
    end

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
end
