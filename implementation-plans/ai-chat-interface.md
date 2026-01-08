# AI Chat Interface - Implementation Plan

## Overview
Enhance the existing AI chat system with financial intelligence and add a CLI tool for command-line interaction. The app already has a functional chat interface (`Chat`, `Assistant`, `AssistantMessage` models) - this plan focuses on adding financial context functions and a standalone CLI tool.

**Key Components:**
- Backend: Financial context functions (tools) for AI to access transaction data, cash flow, spending patterns
- CLI: Standalone command-line tool for quick financial queries
- Web Enhancement: Improved financial insights in existing chat interface

**Sequencing Logic:**
1. Financial context functions (AI tools) for accessing financial data
2. CLI tool implementation with Thor
3. Web interface enhancements
4. Testing and validation
5. Documentation

---

## Table of Contents
1. [Phase 1: Financial Context Functions (AI Tools)](#phase-1)
2. [Phase 2: CLI Tool Implementation](#phase-2)
3. [Phase 3: Web Interface Enhancements](#phase-3)
4. [Phase 4: Testing](#phase-4)
5. [Phase 5: Documentation](#phase-5)

---

## Phase 1: Financial Context Functions (AI Tools) {#phase-1}

**Justification:** Provides AI with ability to access and analyze financial data. Implements function calling pattern already established in `Assistant` class.

### 1.1 Create Base Financial Function Class

- [ ] Create `app/models/assistant/functions/base_financial_function.rb`

**Novel Implementation - Full Detail Required:**

```ruby
# app/models/assistant/functions/base_financial_function.rb

module Assistant
  module Functions
    # Base class for financial data functions that AI can call
    #
    # Provides common functionality for accessing family financial data
    # and formatting responses for AI consumption.
    #
    # @abstract Subclass and override {#call} to implement function logic
    #
    # @example Creating a new function
    #   class GetAccountBalance < BaseFinancialFunction
    #     def name
    #       "get_account_balance"
    #     end
    #
    #     def description
    #       "Get the current balance of a specific account"
    #     end
    #
    #     def parameters
    #       {
    #         type: "object",
    #         properties: {
    #           account_name: { type: "string", description: "Name of the account" }
    #         },
    #         required: ["account_name"]
    #       }
    #     end
    #
    #     def call(account_name:)
    #       # Implementation
    #     end
    #   end
    class BaseFinancialFunction
      attr_reader :user

      def initialize(user)
        @user = user
      end

      # @return [Family] The user's family
      def family
        @family ||= user.family
      end

      # @return [String] Function name for AI to call
      # @abstract Must be implemented by subclass
      def name
        raise NotImplementedError
      end

      # @return [String] Human-readable description of what this function does
      # @abstract Must be implemented by subclass
      def description
        raise NotImplementedError
      end

      # @return [Hash] JSON Schema for function parameters
      # @abstract Must be implemented by subclass
      def parameters
        raise NotImplementedError
      end

      # Execute the function with given parameters
      #
      # @param kwargs [Hash] Function parameters
      # @return [Hash, String] Result data or error message
      # @abstract Must be implemented by subclass
      def call(**kwargs)
        raise NotImplementedError
      end

      protected

        # Parse a date string with multiple format support
        #
        # @param date_string [String] Date in various formats
        # @return [Date, nil] Parsed date or nil if invalid
        def parse_date(date_string)
          return Date.current if date_string.to_s.downcase == "today"
          return Date.current - 1.day if date_string.to_s.downcase == "yesterday"

          Date.parse(date_string)
        rescue Date::Error, ArgumentError
          nil
        end

        # Format money for AI consumption
        #
        # @param money [Money] Money object to format
        # @return [Hash] Formatted money data
        def format_money(money)
          {
            amount: money.to_f,
            formatted: money.format,
            currency: money.currency.iso_code
          }
        end

        # Format array of transactions for AI
        #
        # @param transactions [Array<Transaction>] Transactions to format
        # @param limit [Integer] Maximum number to return
        # @return [Array<Hash>] Formatted transaction data
        def format_transactions(transactions, limit: 10)
          transactions.limit(limit).map do |txn|
            {
              id: txn.id,
              date: txn.entry.date.to_s,
              name: txn.name,
              amount: format_money(Money.new(txn.entry.amount.abs, txn.entry.currency)),
              category: txn.category&.name,
              account: txn.entry.account.name,
              notes: txn.notes
            }
          end
        end
    end
  end
end
```

### 1.2 Implement Core Financial Functions

- [ ] Create `app/models/assistant/functions/get_transactions.rb`

**Novel Implementation - Full Detail:**

```ruby
# app/models/assistant/functions/get_transactions.rb

module Assistant
  module Functions
    # Retrieves transactions for the family based on various filters
    #
    # Allows AI to query transactions by date range, category, account,
    # amount range, and search keywords.
    class GetTransactions < BaseFinancialFunction
      def name
        "get_transactions"
      end

      def description
        "Search and retrieve transactions. Can filter by date range, category, account, amount range, or search text. Returns up to 50 transactions."
      end

      def parameters
        {
          type: "object",
          properties: {
            start_date: {
              type: "string",
              description: "Start date in YYYY-MM-DD format or 'today', 'yesterday'. Defaults to 30 days ago."
            },
            end_date: {
              type: "string",
              description: "End date in YYYY-MM-DD format or 'today'. Defaults to today."
            },
            category: {
              type: "string",
              description: "Filter by category name (e.g., 'Groceries', 'Dining')"
            },
            account: {
              type: "string",
              description: "Filter by account name"
            },
            min_amount: {
              type: "number",
              description: "Minimum transaction amount"
            },
            max_amount: {
              type: "number",
              description: "Maximum transaction amount"
            },
            search: {
              type: "string",
              description: "Search in transaction names and notes"
            },
            limit: {
              type: "integer",
              description: "Maximum number of transactions to return (default 20, max 50)"
            }
          }
        }
      end

      def call(start_date: nil, end_date: nil, category: nil, account: nil, min_amount: nil, max_amount: nil, search: nil, limit: 20)
        # Parse dates
        start_date = parse_date(start_date) || 30.days.ago.to_date
        end_date = parse_date(end_date) || Date.current

        # Validate limit
        limit = [[limit.to_i, 1].max, 50].min

        # Build query
        transactions = family.transactions
          .joins(:entry)
          .where(entries: { date: start_date..end_date })
          .order("entries.date DESC")

        # Apply filters
        if category.present?
          transactions = transactions.joins(:category).where("categories.name ILIKE ?", "%#{category}%")
        end

        if account.present?
          transactions = transactions.joins(entry: :account).where("accounts.name ILIKE ?", "%#{account}%")
        end

        if min_amount.present?
          transactions = transactions.where("ABS(entries.amount) >= ?", min_amount)
        end

        if max_amount.present?
          transactions = transactions.where("ABS(entries.amount) <= ?", max_amount)
        end

        if search.present?
          transactions = transactions.where("transactions.name ILIKE ? OR transactions.notes ILIKE ?", "%#{search}%", "%#{search}%")
        end

        # Format results
        {
          count: transactions.count,
          transactions: format_transactions(transactions, limit: limit),
          period: {
            start_date: start_date.to_s,
            end_date: end_date.to_s
          }
        }
      rescue => e
        { error: "Failed to retrieve transactions: #{e.message}" }
      end
    end
  end
end
```

- [ ] Create `app/models/assistant/functions/get_spending_by_category.rb`

**Novel Implementation:**

```ruby
# app/models/assistant/functions/get_spending_by_category.rb

module Assistant
  module Functions
    # Analyzes spending breakdown by category for a time period
    class GetSpendingByCategory < BaseFinancialFunction
      def name
        "get_spending_by_category"
      end

      def description
        "Get spending breakdown by category for a time period. Shows how much was spent in each category."
      end

      def parameters
        {
          type: "object",
          properties: {
            start_date: {
              type: "string",
              description: "Start date in YYYY-MM-DD format. Defaults to start of current month."
            },
            end_date: {
              type: "string",
              description: "End date in YYYY-MM-DD format. Defaults to today."
            },
            top_n: {
              type: "integer",
              description: "Number of top categories to return (default 10)"
            }
          }
        }
      end

      def call(start_date: nil, end_date: nil, top_n: 10)
        start_date = parse_date(start_date) || Date.current.beginning_of_month
        end_date = parse_date(end_date) || Date.current

        top_n = [[top_n.to_i, 1].max, 20].min

        # Query spending by category
        spending = Transaction
          .joins(:entry, :category)
          .joins(entry: :account)
          .where(accounts: { family_id: family.id })
          .where(entries: { date: start_date..end_date, excluded: false })
          .where("entries.amount > 0") # Expenses are positive amounts
          .group("categories.id", "categories.name")
          .select("categories.name, SUM(entries.amount) as total_amount, COUNT(*) as transaction_count, entries.currency")
          .order("total_amount DESC")
          .limit(top_n)

        categories = spending.map do |row|
          {
            category: row.name,
            amount: format_money(Money.new(row.total_amount, row.currency)),
            transaction_count: row.transaction_count
          }
        end

        total_spending = categories.sum { |c| c[:amount][:amount] }

        {
          categories: categories,
          total_spending: {
            amount: total_spending,
            formatted: Money.new(total_spending * 100, family.currency).format,
            currency: family.currency
          },
          period: {
            start_date: start_date.to_s,
            end_date: end_date.to_s
          }
        }
      rescue => e
        { error: "Failed to analyze spending: #{e.message}" }
      end
    end
  end
end
```

- [ ] Create `app/models/assistant/functions/get_account_balances.rb`

**Standard Pattern:**

Similar structure to above functions:
- Queries `family.accounts.visible`
- Returns balance, name, type for each account
- Formats with `format_money` helper
- Groups by asset/liability classification

- [ ] Create `app/models/assistant/functions/get_cash_flow.rb`

**Standard Pattern:**

Calculates income and expenses for a period:
- Uses `family.income_statement`
- Returns income, expenses, net cash flow
- Includes comparison to previous period if requested

- [ ] Create `app/models/assistant/functions/get_net_worth.rb`

**Standard Pattern:**

Leverages the `NetWorth` service from Phase 1 of net worth timeline:
- Instantiates `NetWorth.new(family)`
- Returns current net worth and historical trend
- Optionally includes breakdown by account type

### 1.3 Register Functions with Assistant

- [ ] Update `app/models/assistant/configurable.rb` to register financial functions

**Standard Pattern - Reference Existing:**

Follow the existing pattern in the `Configurable` module. Add financial functions to the configuration:

```ruby
# Add to config hash
functions: [
  Assistant::Functions::GetTransactions,
  Assistant::Functions::GetSpendingByCategory,
  Assistant::Functions::GetAccountBalances,
  Assistant::Functions::GetCashFlow,
  Assistant::Functions::GetNetWorth
]
```

### 1.4 Add Tests for Functions

- [ ] Create `test/models/assistant/functions/get_transactions_test.rb`

**Standard Pattern - Reference Existing Test Patterns:**

Follow Minitest patterns from existing model tests:
- Test with valid parameters
- Test date parsing
- Test filtering (category, account, amount)
- Test search functionality
- Test limit validation
- Test error handling

---

## Phase 2: CLI Tool Implementation {#phase-2}

**Justification:** Provides command-line interface for quick financial queries without opening the web app. Follows Ruby CLI conventions using Thor.

### 2.1 Create CLI Entry Point

- [ ] Create `bin/maybe-ai` executable

**Novel CLI Implementation - Full Detail:**

```ruby
#!/usr/bin/env ruby
# bin/maybe-ai

require_relative "../config/environment"
require "thor"
require "io/console"

# CLI tool for interacting with Maybe AI assistant from command line
#
# Provides quick access to financial data and insights without opening the web app.
#
# @example Basic usage
#   bin/maybe-ai chat "How much did I spend on groceries this month?"
#   bin/maybe-ai transactions --category "Dining" --days 30
#   bin/maybe-ai net-worth
#
# @example Interactive mode
#   bin/maybe-ai interactive
class MaybeAI < Thor
  class_option :user_id, type: :numeric, desc: "User ID (defaults to first user)"
  class_option :debug, type: :boolean, desc: "Show debug information"

  desc "chat PROMPT", "Ask the AI assistant a question about your finances"
  long_desc <<-LONGDESC
    Chat with the Maybe AI assistant from the command line.

    Examples:
      bin/maybe-ai chat "What's my net worth?"
      bin/maybe-ai chat "Show me my largest expenses this month"
      bin/maybe-ai chat "How much did I spend on dining last week?"
  LONGDESC
  def chat(prompt)
    user = get_user
    print_debug("User: #{user.email}") if options[:debug]

    print "\nThinking...\n\n"

    # Create a temporary chat
    chat = user.chats.create!(
      title: prompt.first(80)
    )

    # Create user message
    message = chat.messages.create!(
      type: "UserMessage",
      content: prompt,
      ai_model: Chat.default_model
    )

    # Get assistant response
    assistant = Assistant.for_chat(chat)
    response_text = ""

    # Capture response text
    assistant.respond_to(message)

    # Get the response
    response = chat.conversation_messages.where(type: "AssistantMessage").last

    if response
      print_response(response.content)
    elsif chat.error.present?
      print_error("Error: #{JSON.parse(chat.error)['message']}")
    else
      print_error("No response from assistant")
    end

    # Clean up
    chat.destroy unless options[:keep_chat]

  rescue => e
    print_error("Failed to chat: #{e.message}")
    print_debug(e.backtrace.join("\n")) if options[:debug]
    exit 1
  end

  desc "transactions [OPTIONS]", "List recent transactions"
  option :days, type: :numeric, default: 30, desc: "Number of days to look back"
  option :category, type: :string, desc: "Filter by category"
  option :account, type: :string, desc: "Filter by account"
  option :limit, type: :numeric, default: 20, desc: "Number of transactions to show"
  long_desc <<-LONGDESC
    List recent transactions with optional filters.

    Examples:
      bin/maybe-ai transactions --days 7
      bin/maybe-ai transactions --category "Groceries" --days 30
      bin/maybe-ai transactions --account "Chase Checking" --limit 10
  LONGDESC
  def transactions
    user = get_user
    function = Assistant::Functions::GetTransactions.new(user)

    result = function.call(
      start_date: options[:days].days.ago.to_date.to_s,
      end_date: Date.current.to_s,
      category: options[:category],
      account: options[:account],
      limit: options[:limit]
    )

    if result[:error]
      print_error(result[:error])
      exit 1
    end

    print_transactions_table(result)
  rescue => e
    print_error("Failed to get transactions: #{e.message}")
    exit 1
  end

  desc "spending [OPTIONS]", "Show spending breakdown by category"
  option :days, type: :numeric, default: 30, desc: "Number of days to look back"
  option :top, type: :numeric, default: 10, desc: "Number of top categories to show"
  long_desc <<-LONGDESC
    Show spending breakdown by category for a time period.

    Examples:
      bin/maybe-ai spending --days 30
      bin/maybe-ai spending --days 7 --top 5
  LONGDESC
  def spending
    user = get_user
    function = Assistant::Functions::GetSpendingByCategory.new(user)

    result = function.call(
      start_date: options[:days].days.ago.to_date.to_s,
      end_date: Date.current.to_s,
      top_n: options[:top]
    )

    if result[:error]
      print_error(result[:error])
      exit 1
    end

    print_spending_table(result)
  rescue => e
    print_error("Failed to get spending: #{e.message}")
    exit 1
  end

  desc "net-worth", "Show current net worth and recent trend"
  def net_worth
    user = get_user
    net_worth = NetWorth.new(user.family)

    current = net_worth.current
    timeline = net_worth.timeline(
      start_date: 1.year.ago.to_date,
      end_date: Date.current,
      interval: :monthly
    )

    print_net_worth_summary(current, timeline)
  rescue => e
    print_error("Failed to get net worth: #{e.message}")
    exit 1
  end

  desc "interactive", "Start an interactive chat session"
  long_desc <<-LONGDESC
    Start an interactive session where you can have a conversation
    with the AI assistant.

    Type 'exit', 'quit', or 'q' to end the session.
  LONGDESC
  def interactive
    user = get_user
    chat = user.chats.create!(
      title: "CLI Session #{Time.current.strftime('%Y-%m-%d %H:%M')}"
    )

    puts "\nMaybe AI - Interactive Session"
    puts "Type 'exit', 'quit', or 'q' to end the session.\n\n"

    loop do
      print "You: "
      input = gets&.chomp
      break if input.nil? || %w[exit quit q].include?(input.downcase)

      next if input.strip.empty?

      print "\nAssistant: "

      # Create user message
      message = chat.messages.create!(
        type: "UserMessage",
        content: input,
        ai_model: Chat.default_model
      )

      # Get assistant response
      assistant = Assistant.for_chat(chat)
      assistant.respond_to(message)

      # Get the response
      response = chat.conversation_messages.where(type: "AssistantMessage").last

      if response
        puts response.content
      elsif chat.error.present?
        puts "[Error: #{JSON.parse(chat.error)['message']}]"
      else
        puts "[No response]"
      end

      puts "\n"
    end

    puts "\nGoodbye!\n"
    chat.destroy unless options[:keep_chat]
  end

  private

    def get_user
      user = if options[:user_id]
        User.find(options[:user_id])
      else
        User.first
      end

      unless user
        print_error("No user found. Specify --user-id=ID")
        exit 1
      end

      user
    end

    def print_response(text)
      puts text
      puts
    end

    def print_error(message)
      puts "\033[31m#{message}\033[0m" # Red text
    end

    def print_debug(message)
      puts "\033[90m[DEBUG] #{message}\033[0m" # Gray text
    end

    def print_transactions_table(result)
      puts "\nTransactions (#{result[:period][:start_date]} to #{result[:period][:end_date]})"
      puts "Total: #{result[:count]} transactions\n\n"

      # Print table header
      printf "%-12s  %-30s  %-20s  %15s\n", "Date", "Description", "Category", "Amount"
      puts "-" * 80

      result[:transactions].each do |txn|
        printf "%-12s  %-30s  %-20s  %15s\n",
          txn[:date],
          txn[:name][0, 30],
          (txn[:category] || "Uncategorized")[0, 20],
          txn[:amount][:formatted]
      end

      puts
    end

    def print_spending_table(result)
      puts "\nSpending by Category (#{result[:period][:start_date]} to #{result[:period][:end_date]})"
      puts "Total: #{result[:total_spending][:formatted]}\n\n"

      # Print table header
      printf "%-30s  %15s  %10s\n", "Category", "Amount", "Count"
      puts "-" * 60

      result[:categories].each do |cat|
        printf "%-30s  %15s  %10d\n",
          cat[:category][0, 30],
          cat[:amount][:formatted],
          cat[:transaction_count]
      end

      puts
    end

    def print_net_worth_summary(current, timeline)
      summary = timeline[:summary]

      puts "\nNet Worth Summary"
      puts "=" * 50
      puts
      printf "Current Net Worth:   %s\n", current.format
      printf "1 Year Change:       %s (%s%%)\n",
        summary[:total_change].format,
        summary[:percent_change]
      puts
    end
end

# Run CLI
MaybeAI.start(ARGV)
```

- [ ] Make executable: `chmod +x bin/maybe-ai`

### 2.2 Add CLI Configuration

- [ ] Create `.maybe-ai.yml` config file support for user preferences

**Standard Pattern:**

```ruby
# Allow users to create ~/.maybe-ai.yml with:
# user_id: 123
# default_model: "claude-3-5-sonnet-20241022"
# timezone: "America/Los_Angeles"
```

### 2.3 Test CLI Tool

- [ ] Manual testing of all CLI commands
- [ ] Test error handling
- [ ] Test with multiple users
- [ ] Test interactive mode

---

## Phase 3: Web Interface Enhancements {#phase-3}

**Justification:** Improves the existing web chat interface with financial context and quick action buttons.

### 3.1 Add Financial Context Sample Questions

- [ ] Update `app/views/chats/show.html.erb` to include financial sample questions

**Standard Pattern - Reference Existing:**

Follow pattern from existing sample questions in chat views. Add financial-specific examples:

```erb
<%# Add to sample questions when chat is empty %>
<% if @chat.messages.empty? %>
  <div class="grid grid-cols-2 gap-4 mt-8">
    <button data-action="click->chat#submitSampleQuestion"
            data-chat-question-param="What's my net worth?"
            class="p-4 border border-primary rounded-lg hover:bg-gray-50 text-left">
      <div class="font-medium">💰 Net Worth</div>
      <div class="text-sm text-subdued">Check current net worth</div>
    </button>

    <button data-action="click->chat#submitSampleQuestion"
            data-chat-question-param="Show me my spending by category this month"
            class="p-4 border border-primary rounded-lg hover:bg-gray-50 text-left">
      <div class="font-medium">📊 Category Spending</div>
      <div class="text-sm text-subdued">Analyze spending patterns</div>
    </button>

    <%# Add more sample questions %>
  </div>
<% end %>
```

### 3.2 Add Quick Action Menu

- [ ] Create quick action menu component in chat interface
- [ ] Add buttons for common financial queries

**Standard Pattern:**

Use DS::Menu component for quick actions dropdown.

---

## Phase 4: Testing {#phase-4}

**Justification:** Ensures reliability of AI functions and CLI tool.

### 4.1 Function Tests

- [ ] Test all financial functions with fixtures
- [ ] Test date parsing edge cases
- [ ] Test error handling
- [ ] Test with different family configurations

### 4.2 Integration Tests

- [ ] Test full chat flow with financial functions
- [ ] Test function calling from web interface
- [ ] Test CLI tool execution

**Standard Pattern:**

Follow existing test patterns for Assistant and Chat models.

---

## Phase 5: Documentation {#phase-5}

**Justification:** Documents new capabilities for users and developers.

### 5.1 Add CLI Documentation

- [ ] Create `docs/cli-tool.md` with usage examples
- [ ] Add to README.md

**Standard Content:**

```markdown
# Maybe AI CLI Tool

The Maybe AI CLI tool allows you to interact with your financial data from the command line.

## Installation

The tool is included with Maybe. No additional installation needed.

## Usage

### Quick queries:
```bash
bin/maybe-ai chat "What's my net worth?"
bin/maybe-ai transactions --category "Dining" --days 30
bin/maybe-ai spending --days 7
bin/maybe-ai net-worth
```

### Interactive mode:
```bash
bin/maybe-ai interactive
```

## Available Commands

- `chat` - Ask a question
- `transactions` - List transactions
- `spending` - Show spending breakdown
- `net-worth` - Show net worth summary
- `interactive` - Start interactive session
```

### 5.2 Update i18n

- [ ] Add translations for new chat features

```yaml
en:
  chats:
    financial_questions:
      net_worth: "What's my net worth?"
      spending: "Show me my spending by category this month"
      transactions: "What were my largest expenses this week?"
```

### 5.3 Add CHANGELOG Entry

```markdown
## [Unreleased]

### Added
- AI Chat: Financial intelligence functions for accessing transaction data, cash flow, and spending patterns
- CLI Tool: Command-line interface for quick financial queries (`bin/maybe-ai`)
- Chat UI: Financial sample questions and quick actions in web interface
```

---

## Validation Steps

After implementing all phases, verify:

- [ ] Chat with AI about transactions works in web interface
- [ ] AI can access and analyze financial data correctly
- [ ] CLI tool runs successfully: `bin/maybe-ai chat "What's my net worth?"`
- [ ] CLI transactions command works: `bin/maybe-ai transactions --days 7`
- [ ] CLI spending command works: `bin/maybe-ai spending`
- [ ] CLI interactive mode works: `bin/maybe-ai interactive`
- [ ] Sample questions in web UI work correctly
- [ ] Function calling integrates with existing Assistant infrastructure
- [ ] All tests pass: `bin/rails test`
- [ ] CLI handles errors gracefully
- [ ] Multi-user support works in CLI with --user-id flag
