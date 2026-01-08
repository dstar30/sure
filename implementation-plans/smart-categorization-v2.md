# Smart Categorization v2 - Implementation Plan

## Table of Contents

1. [Overview](#1-overview)
2. [Requirements](#2-requirements)
   - 2.1 [User Needs](#21-user-needs)
   - 2.2 [Functional Requirements](#22-functional-requirements)
   - 2.3 [Non-Functional Requirements](#23-non-functional-requirements)
3. [Technical Specification](#3-technical-specification)
   - 3.1 [Data Model](#31-data-model)
   - 3.2 [Pattern Learning Engine](#32-pattern-learning-engine)
   - 3.3 [String Similarity Algorithm](#33-string-similarity-algorithm)
   - 3.4 [Confidence Scoring](#34-confidence-scoring)
   - 3.5 [Integration Architecture](#35-integration-architecture)
   - 3.6 [UI Components](#36-ui-components)
4. [Implementation Plan](#4-implementation-plan)
   - 4.1 [Phase 1: Prerequisites & Data Model](#41-phase-1-prerequisites--data-model)
   - 4.2 [Phase 2: Pattern Learning Engine](#42-phase-2-pattern-learning-engine)
   - 4.3 [Phase 3: Jaro-Winkler Similarity Matching](#43-phase-3-jaro-winkler-similarity-matching)
   - 4.4 [Phase 4: Pattern Matching & Confidence Scoring](#44-phase-4-pattern-matching--confidence-scoring)
   - 4.5 [Phase 5: Auto-Categorization Integration](#45-phase-5-auto-categorization-integration)
   - 4.6 [Phase 6: Bulk Categorization UI](#46-phase-6-bulk-categorization-ui)
   - 4.7 [Phase 7: Transaction Form Suggestions](#47-phase-7-transaction-form-suggestions)
   - 4.8 [Phase 8: Testing & Documentation](#48-phase-8-testing--documentation)

---

## 1. Overview

**What We're Building:**
A smart categorization system (v2) that learns from historical transaction patterns to automatically suggest and apply categories to new transactions. The system uses statistical pattern matching and fuzzy string similarity (Jaro-Winkler algorithm) to match merchants and transaction names against successfully categorized transactions, providing high-confidence category suggestions.

**Key Components:**
- `CategorizationPattern` model - stores learned merchant-category associations
- `PatternLearner` service - incrementally learns patterns from user and rule categorizations
- `StringSimilarity::JaroWinkler` - fuzzy matching for merchant name variations
- `PatternMatcher` service - finds best category match with confidence scoring
- Integration into existing enrichment system (new source: `pattern_match`)
- Bulk categorization UI for reviewing and applying suggestions
- Inline category suggestions in transaction edit form

**Sequencing Logic:**
1. **Data foundation first** - Pattern storage model and schema
2. **Core algorithms** - Pattern learning and Jaro-Winkler similarity
3. **Matching engine** - Pattern matcher with confidence scoring
4. **Integration** - Add to enrichment pipeline (between rules and AI)
5. **UI components** - Bulk categorization and form suggestions
6. **Testing & docs** - Comprehensive validation

**Key Design Decisions:**
- **75% confidence threshold** for auto-categorization (conservative, high quality)
- **Jaro-Winkler algorithm** for string similarity (good for name variations)
- **Learn from user + rule categorizations** (highest quality training data)
- **Incremental learning** (no initial batch training, update as users categorize)
- **Database-backed patterns** (indexed for performance, prunable)
- **Respect enrichment locks** (user overrides always win)

---

## 2. Requirements

### 2.1 User Needs

**Primary User Stories:**
- As a user, I want my recurring transactions to be automatically categorized correctly
- As a user, I want the system to learn from my categorization choices
- As a user, I want suggestions when categorizing similar transactions
- As a user, I want to quickly categorize multiple uncategorized transactions at once
- As a user, I want to trust that auto-categorization won't make frequent mistakes

**Secondary User Stories:**
- As a user, I want to see why the system suggested a particular category
- As a user, I want to override incorrect suggestions
- As a user, I want the system to handle merchant name variations (e.g., "STARBUCKS #123" and "Starbucks Store 456")
- As a user, I want categorization to work across different transaction sources (Plaid, SimpleFIN, manual)

### 2.2 Functional Requirements

**FR-1: Pattern Learning**
- Learn merchant-category associations from user-categorized transactions
- Learn from rule-based categorizations
- Incrementally update patterns as new categorizations occur
- Store normalized merchant names for fuzzy matching
- Track match frequency and recency for confidence calculation

**FR-2: String Similarity Matching**
- Implement Jaro-Winkler algorithm for fuzzy merchant name matching
- Normalize merchant names (lowercase, remove special chars, trim)
- Handle common merchant name variations (store numbers, location codes)
- Similarity threshold ≥80% for fuzzy matches

**FR-3: Confidence Scoring**
- Calculate confidence based on:
  - Match frequency (how often merchant → category)
  - String similarity (exact vs fuzzy match)
  - Recency (recent patterns weighted higher)
- Only suggest categories with ≥75% confidence
- Provide confidence level indicator (high/medium/low)

**FR-4: Auto-Categorization**
- Automatically categorize transactions during import if confidence ≥75%
- Use enrichment system with source: `pattern_match`
- Respect locked attributes (user overrides take precedence)
- Priority: Rules → Pattern Match → AI → Manual

**FR-5: Bulk Categorization**
- Display all uncategorized transactions in table view
- Show suggested category with confidence indicator
- Allow accepting/rejecting suggestions in bulk
- Preview changes before applying
- Apply categorizations in background job for large datasets

**FR-6: Inline Suggestions**
- Show category suggestions in transaction edit form (new transactions)
- Display top 3 suggestions with confidence levels
- Allow one-click selection of suggested category
- Explain suggestion basis (e.g., "Based on similar transactions at Starbucks")

**FR-7: Pattern Management**
- Prune low-confidence patterns periodically (< 5 matches over 6 months)
- Merge duplicate patterns for same merchant variants
- Allow disabling pattern-based categorization per family (opt-out)

### 2.3 Non-Functional Requirements

**Performance:**
- Pattern matching should complete within 100ms for single transaction
- Bulk categorization (100 transactions) should complete within 5 seconds
- Database queries optimized with appropriate indexes
- Pattern pruning runs daily in background (off-peak hours)

**Accuracy:**
- Target 90%+ accuracy for high-confidence (≥75%) suggestions
- False positive rate < 5% for auto-categorization
- Merchant name normalization handles 95%+ common variations

**Maintainability:**
- Jaro-Winkler algorithm implemented as reusable utility class
- Pattern learning logic decoupled from transaction import
- Confidence calculation configurable via settings
- Comprehensive test coverage (≥90% for core algorithms)

**Scalability:**
- Support families with 10,000+ transactions
- Pattern table size managed via pruning (target < 1000 patterns per family)
- Efficient database indexes for pattern lookups

---

## 3. Technical Specification

### 3.1 Data Model

#### CategorizationPattern Model

**Table:** `categorization_patterns`

**Purpose:** Store learned merchant-category associations for pattern-based categorization

**Columns:**
```ruby
t.references :family, null: false, foreign_key: true, index: true
t.references :category, null: false, foreign_key: true
t.string :merchant_name, null: false          # Original merchant name
t.string :merchant_name_normalized, null: false  # Normalized for matching
t.string :transaction_name_pattern           # Optional: common transaction name pattern
t.integer :match_count, default: 1, null: false  # Number of times this pattern matched
t.decimal :confidence_score, precision: 5, scale: 2  # Calculated confidence (0.00-1.00)
t.datetime :last_matched_at                  # Last time pattern was used
t.datetime :created_at, null: false
t.datetime :updated_at, null: false
```

**Indexes:**
```ruby
add_index :categorization_patterns, [:family_id, :merchant_name_normalized, :category_id],
  unique: true, name: "idx_cat_patterns_on_family_merchant_category"

add_index :categorization_patterns, [:family_id, :confidence_score],
  name: "idx_cat_patterns_on_family_confidence"

add_index :categorization_patterns, :last_matched_at,
  name: "idx_cat_patterns_on_last_matched"
```

**Model Structure:**
```ruby
class CategorizationPattern < ApplicationRecord
  belongs_to :family
  belongs_to :category

  validates :merchant_name, presence: true
  validates :merchant_name_normalized, presence: true
  validates :match_count, numericality: { greater_than: 0 }
  validates :confidence_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

  scope :for_merchant, ->(normalized_name) { where(merchant_name_normalized: normalized_name) }
  scope :high_confidence, -> { where("confidence_score >= ?", 0.75) }
  scope :recent, -> { where("last_matched_at > ?", 6.months.ago) }
  scope :stale, -> { where("last_matched_at IS NULL OR last_matched_at <= ?", 6.months.ago) }
  scope :low_usage, -> { where("match_count < ?", 5) }

  # Normalize merchant name for consistent matching
  def self.normalize_merchant_name(name)
    return "" if name.blank?

    # Lowercase, remove special characters, collapse whitespace
    normalized = name.downcase
      .gsub(/[^a-z0-9\s]/, " ")  # Replace special chars with space
      .gsub(/\s+/, " ")           # Collapse multiple spaces
      .strip

    # Remove common patterns (store numbers, location codes)
    normalized.gsub(/\b(store|shop|location|#)\s*\d+\b/, "")
      .gsub(/\s+/, " ")
      .strip
  end
end
```

### 3.2 Pattern Learning Engine

**Purpose:** Learn merchant-category associations from successful categorizations

**Learning Sources:**
1. User-confirmed categorizations (highest quality)
2. Rule-based categorizations (high quality)
3. NOT from AI categorizations (may have errors)

**Learning Triggers:**
- After user manually sets category on transaction
- After rule applies category to transaction
- NOT during initial import (only after enrichment)

**Pattern Update Logic:**
```ruby
# When transaction is categorized:
# 1. Extract merchant name (or transaction name if no merchant)
# 2. Normalize merchant name
# 3. Find or create pattern for (family, normalized_merchant, category)
# 4. Increment match_count
# 5. Update last_matched_at
# 6. Recalculate confidence_score
```

**Confidence Calculation:**
```ruby
# Multi-factor confidence score
confidence = (frequency_factor * 0.6) + (recency_factor * 0.3) + (specificity_factor * 0.1)

# Frequency factor: more matches = higher confidence (caps at 20 matches)
frequency_factor = min(match_count / 20.0, 1.0)

# Recency factor: recent matches weighted higher
days_since_last_match = (Time.current - last_matched_at) / 1.day
recency_factor = max(0, 1.0 - (days_since_last_match / 180.0))  # Decays over 6 months

# Specificity factor: longer, more specific merchant names = higher confidence
specificity_factor = min(merchant_name_normalized.length / 20.0, 1.0)
```

### 3.3 String Similarity Algorithm

**Algorithm:** Jaro-Winkler Distance

**Purpose:** Match merchant name variations (e.g., "STARBUCKS" and "Starbucks Coffee #123")

**Jaro-Winkler Formula:**
```
jaro_winkler = jaro_similarity + (prefix_length * prefix_scale * (1 - jaro_similarity))

where:
- jaro_similarity = Jaro distance (0.0 to 1.0)
- prefix_length = length of common prefix (max 4 chars)
- prefix_scale = 0.1 (standard weight for prefix bonus)
```

**Jaro Distance Formula:**
```
jaro = (matches/len1 + matches/len2 + (matches - transpositions)/matches) / 3

where:
- matches = number of matching characters within match_distance
- match_distance = max(len1, len2) / 2 - 1
- transpositions = half the number of transpositions
```

**Implementation Requirements:**
- Return similarity score between 0.0 (no match) and 1.0 (exact match)
- Prefix bonus (Winkler enhancement) for common prefixes up to 4 characters
- Case-insensitive comparison
- Handle empty strings gracefully

**Similarity Threshold:**
- ≥0.80 = fuzzy match (similar enough to suggest)
- ≥0.90 = strong match (high confidence)
- 1.00 = exact match (highest confidence)

### 3.4 Confidence Scoring

**Multi-Factor Confidence Calculation:**

```ruby
def calculate_confidence(pattern:, similarity_score:)
  # Base confidence from pattern quality
  frequency_score = calculate_frequency_score(pattern.match_count)
  recency_score = calculate_recency_score(pattern.last_matched_at)

  # Boost confidence for higher similarity
  similarity_multiplier = similarity_score

  # Combined confidence
  base_confidence = (frequency_score * 0.6) + (recency_score * 0.4)
  final_confidence = base_confidence * similarity_multiplier

  # Cap at 1.0 (100%)
  [final_confidence, 1.0].min
end

def calculate_frequency_score(match_count)
  # More matches = higher confidence, caps at 20 matches
  [match_count / 20.0, 1.0].min
end

def calculate_recency_score(last_matched_at)
  return 0.5 if last_matched_at.nil?  # Default for new patterns

  days_ago = (Time.current - last_matched_at) / 1.day

  # Recent matches (< 30 days) = full score
  return 1.0 if days_ago <= 30

  # Decay linearly over 180 days (6 months)
  decay_rate = (days_ago - 30) / 150.0
  [1.0 - decay_rate, 0.0].max
end
```

**Confidence Levels for UI:**
- **High:** ≥0.85 (green badge, strong recommendation)
- **Medium:** 0.75-0.84 (yellow badge, good suggestion)
- **Low:** 0.60-0.74 (gray badge, possible match, not auto-applied)

**Auto-Categorization Threshold:**
- Only auto-categorize if confidence ≥ 0.75 (75%)

### 3.5 Integration Architecture

**Categorization Priority (Enrichment Pipeline):**
```
1. User Override (locked attribute) → highest priority
2. Rules Engine → applies first
3. Pattern Match (Smart Categorization v2) → NEW tier
4. AI Categorization → fallback for unknowns
5. Manual Entry → lowest priority
```

**Enrichment Source:**
- Add new source: `pattern_match` to `DataEnrichment.sources` enum
- Pattern-based categorizations tracked in `data_enrichments` table
- Enrichment metadata includes: `{ confidence: 0.85, similarity: 0.92, pattern_id: 123 }`

**Integration Points:**

**During Import:**
```ruby
# In Account::ProviderImportAdapter or equivalent
transaction = import_transaction(...)

# After rules, before AI
if transaction.category_id.nil? && transaction.enrichable?(:category_id)
  suggestion = PatternMatcher.new(transaction: transaction, family: family).suggest

  if suggestion && suggestion.confidence >= 0.75
    transaction.enrich_attribute(
      :category_id,
      suggestion.category.id,
      source: :pattern_match,
      metadata: {
        confidence: suggestion.confidence,
        similarity: suggestion.similarity,
        pattern_id: suggestion.pattern.id
      }
    )
  end
end
```

**After User Categorization:**
```ruby
# In TransactionsController#update or wherever category is set
after_save :learn_categorization_pattern

def learn_categorization_pattern
  return unless saved_change_to_category_id?
  return if category_id.nil?

  PatternLearner.learn_from_transaction(self)
end
```

**After Rule Application:**
```ruby
# In Rule::ActionExecutor::SetTransactionCategory
def execute(transaction)
  transaction.enrich_attribute(:category_id, category.id, source: :rule)

  # Learn pattern from rule categorization
  PatternLearner.learn_from_transaction(transaction)
end
```

### 3.6 UI Components

#### Bulk Categorization Page

**Route:** `/transactions/bulk_categorize`

**Features:**
- Table of uncategorized transactions
- Suggested category column with confidence badge
- Checkbox to select transactions
- "Apply Selected" button to bulk categorize
- "Apply All High Confidence" button (≥85% only)
- Filters: date range, account, confidence level

**Table Columns:**
- Date
- Merchant/Description
- Amount
- Suggested Category (with confidence badge)
- Checkbox (select for bulk action)
- Actions (Accept, Reject, Edit)

#### Transaction Form Suggestions

**Location:** Transaction edit form (new transactions only)

**Features:**
- Category dropdown with suggestions section
- Top 3 suggestions shown with confidence indicators
- Tooltip explaining suggestion basis
- One-click to select suggested category
- Standard category picker below suggestions

**Suggestion Display:**
```
┌─────────────────────────────────────────┐
│ Category Suggestions                     │
├─────────────────────────────────────────┤
│ 🟢 Food & Drink (85% confidence)        │
│    Based on 15 similar transactions     │
├─────────────────────────────────────────┤
│ 🟡 Groceries (78% confidence)           │
│    Based on 8 similar transactions      │
├─────────────────────────────────────────┤
│ ⚪ Coffee Shops (65% confidence)        │
│    Based on 3 similar transactions      │
└─────────────────────────────────────────┘
```

---

## 4. Implementation Plan

### 4.1 Phase 1: Prerequisites & Data Model

**Justification:** Implements spec section 3.1 (Data Model). Foundation for pattern storage and retrieval.

**Tasks:**

- [ ] Review existing categorization infrastructure
  - Read `app/models/concerns/enrichable.rb` to understand enrichment system
  - Read `app/models/data_enrichment.rb` to understand source tracking
  - Read `app/models/transaction.rb` to understand categorization hooks
  - Review `app/models/category.rb` and `app/models/merchant.rb` associations
  - Study `app/models/plaid_account/transactions/category_matcher.rb` for existing fuzzy matching patterns

- [ ] Create migration for `categorization_patterns` table
  ```ruby
  # db/migrate/YYYYMMDDHHMMSS_create_categorization_patterns.rb
  class CreateCategorizationPatterns < ActiveRecord::Migration[8.0]
    def change
      create_table :categorization_patterns do |t|
        t.references :family, null: false, foreign_key: true, index: true
        t.references :category, null: false, foreign_key: true
        t.string :merchant_name, null: false
        t.string :merchant_name_normalized, null: false
        t.string :transaction_name_pattern
        t.integer :match_count, default: 1, null: false
        t.decimal :confidence_score, precision: 5, scale: 2
        t.datetime :last_matched_at

        t.timestamps
      end

      # Composite unique index for pattern uniqueness
      add_index :categorization_patterns,
        [:family_id, :merchant_name_normalized, :category_id],
        unique: true,
        name: "idx_cat_patterns_on_family_merchant_category"

      # Index for high-confidence pattern lookups
      add_index :categorization_patterns,
        [:family_id, :confidence_score],
        name: "idx_cat_patterns_on_family_confidence"

      # Index for pruning stale patterns
      add_index :categorization_patterns,
        :last_matched_at,
        name: "idx_cat_patterns_on_last_matched"
    end
  end
  ```

- [ ] Create `CategorizationPattern` model in `app/models/categorization_pattern.rb`
  ```ruby
  # == Schema Information
  #
  # Table name: categorization_patterns
  #
  #  id                       :bigint           not null, primary key
  #  confidence_score         :decimal(5, 2)
  #  last_matched_at          :datetime
  #  match_count              :integer          default(1), not null
  #  merchant_name            :string           not null
  #  merchant_name_normalized :string           not null
  #  transaction_name_pattern :string
  #  created_at               :datetime         not null
  #  updated_at               :datetime         not null
  #  category_id              :bigint           not null
  #  family_id                :bigint           not null
  #
  # Indexes
  #
  #  idx_cat_patterns_on_family_confidence       (family_id,confidence_score)
  #  idx_cat_patterns_on_family_merchant_category (family_id,merchant_name_normalized,category_id) UNIQUE
  #  idx_cat_patterns_on_last_matched            (last_matched_at)
  #  index_categorization_patterns_on_category_id (category_id)
  #  index_categorization_patterns_on_family_id   (family_id)
  #
  class CategorizationPattern < ApplicationRecord
    belongs_to :family
    belongs_to :category

    validates :merchant_name, presence: true
    validates :merchant_name_normalized, presence: true
    validates :match_count, numericality: { greater_than: 0 }
    validates :confidence_score,
      numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 },
      allow_nil: true

    # Scopes for pattern retrieval and management
    scope :for_merchant, ->(normalized_name) {
      where(merchant_name_normalized: normalized_name)
    }

    scope :high_confidence, -> { where("confidence_score >= ?", 0.75) }
    scope :medium_confidence, -> { where("confidence_score >= ? AND confidence_score < ?", 0.60, 0.75) }
    scope :low_confidence, -> { where("confidence_score < ?", 0.60) }

    scope :recent, -> { where("last_matched_at > ?", 6.months.ago) }
    scope :stale, -> {
      where("last_matched_at IS NULL OR last_matched_at <= ?", 6.months.ago)
    }

    scope :low_usage, -> { where("match_count < ?", 5) }

    scope :ordered_by_confidence, -> { order(confidence_score: :desc, match_count: :desc) }

    # Normalize merchant name for consistent pattern matching
    #
    # Normalization steps:
    # 1. Convert to lowercase
    # 2. Remove special characters (replace with space)
    # 3. Collapse multiple spaces
    # 4. Remove common patterns (store numbers, location codes)
    # 5. Trim whitespace
    #
    # @param name [String] Original merchant name
    # @return [String] Normalized merchant name
    #
    # @example
    #   CategorizationPattern.normalize_merchant_name("STARBUCKS Store #1234")
    #   # => "starbucks"
    #
    #   CategorizationPattern.normalize_merchant_name("McDonald's Restaurant")
    #   # => "mcdonald s restaurant"
    #
    def self.normalize_merchant_name(name)
      return "" if name.blank?

      # Lowercase and remove special characters
      normalized = name.downcase
        .gsub(/[^a-z0-9\s]/, " ")  # Replace special chars with space
        .gsub(/\s+/, " ")           # Collapse multiple spaces
        .strip

      # Remove common merchant name patterns
      normalized
        .gsub(/\b(store|shop|location|#|no)\s*\d+\b/i, "")  # "Store 123", "#456"
        .gsub(/\b\d{3,}\b/, "")                               # Long numbers
        .gsub(/\s+/, " ")                                     # Re-collapse spaces
        .strip
    end

    # Increment match count and update last matched timestamp
    #
    # Call this when pattern successfully matches a transaction
    #
    # @return [Boolean] Whether the update succeeded
    def record_match!
      increment!(:match_count)
      update!(last_matched_at: Time.current)
      recalculate_confidence!
    end

    # Recalculate confidence score based on current pattern statistics
    #
    # Confidence factors:
    # - Frequency: more matches = higher confidence (caps at 20 matches)
    # - Recency: recent matches weighted higher (6-month decay)
    # - Specificity: longer merchant names = higher confidence
    #
    # @return [Float] Updated confidence score (0.0 to 1.0)
    def recalculate_confidence!
      frequency_score = calculate_frequency_score
      recency_score = calculate_recency_score
      specificity_score = calculate_specificity_score

      new_confidence = (frequency_score * 0.6) +
                       (recency_score * 0.3) +
                       (specificity_score * 0.1)

      update!(confidence_score: new_confidence.round(2))
      new_confidence
    end

    # Get human-readable confidence level
    #
    # @return [Symbol] :high, :medium, or :low
    def confidence_level
      return :low if confidence_score.nil? || confidence_score < 0.60
      return :medium if confidence_score < 0.85
      :high
    end

    # Check if pattern meets auto-categorization threshold
    #
    # @return [Boolean] True if confidence >= 75%
    def auto_categorizable?
      confidence_score.present? && confidence_score >= 0.75
    end

    private

    # Calculate frequency score component
    # More matches = higher confidence, with diminishing returns
    # Caps at 20 matches for max score
    def calculate_frequency_score
      [match_count / 20.0, 1.0].min
    end

    # Calculate recency score component
    # Recent matches weighted higher, decays over 6 months
    def calculate_recency_score
      return 0.5 if last_matched_at.nil?  # Default for new patterns

      days_ago = (Time.current - last_matched_at) / 1.day

      # Recent matches (< 30 days) get full score
      return 1.0 if days_ago <= 30

      # Linear decay over next 150 days (total 180 days / 6 months)
      decay_rate = (days_ago - 30) / 150.0
      [1.0 - decay_rate, 0.0].max
    end

    # Calculate specificity score component
    # Longer, more specific merchant names = higher confidence
    def calculate_specificity_score
      return 0.5 if merchant_name_normalized.blank?

      # 20+ character names get full score
      [merchant_name_normalized.length / 20.0, 1.0].min
    end
  end
  ```

- [ ] Add association to Family model
  ```ruby
  # In app/models/family.rb, add:
  has_many :categorization_patterns, dependent: :destroy
  ```

- [ ] Add association to Category model
  ```ruby
  # In app/models/category.rb, add:
  has_many :categorization_patterns, dependent: :destroy
  ```

- [ ] Run migrations: `bin/rails db:migrate`

- [ ] Create fixture data in `test/fixtures/categorization_patterns.yml`
  ```yaml
  starbucks_food_drink:
    family: dylan_family
    category: food_and_drink
    merchant_name: "STARBUCKS STORE #1234"
    merchant_name_normalized: "starbucks"
    match_count: 15
    confidence_score: 0.88
    last_matched_at: <%= 2.days.ago %>

  shell_gas:
    family: dylan_family
    category: transportation
    merchant_name: "SHELL OIL 12345678"
    merchant_name_normalized: "shell oil"
    match_count: 8
    confidence_score: 0.72
    last_matched_at: <%= 5.days.ago %>

  amazon_shopping:
    family: dylan_family
    category: shopping
    merchant_name: "AMAZON.COM"
    merchant_name_normalized: "amazon com"
    match_count: 25
    confidence_score: 0.95
    last_matched_at: <%= 1.day.ago %>
  ```

- [ ] Write model tests in `test/models/categorization_pattern_test.rb`
  - Test normalization logic with various merchant names
  - Test confidence calculation for different scenarios
  - Test `record_match!` updates timestamps and count
  - Test scopes (high_confidence, recent, stale, etc.)
  - Test `auto_categorizable?` threshold
  - Test confidence level categorization

### 4.2 Phase 2: Pattern Learning Engine

**Justification:** Implements spec section 3.2 (Pattern Learning Engine). Core logic for building patterns from historical data.

**Tasks:**

- [ ] Create `PatternLearner` service in `app/models/pattern_learner.rb`
  ```ruby
  # frozen_string_literal: true

  # Service for learning categorization patterns from transactions
  #
  # Learns merchant-category associations from:
  # - User-confirmed categorizations (manual edits)
  # - Rule-based categorizations
  #
  # Does NOT learn from:
  # - AI categorizations (may contain errors)
  # - Uncategorized transactions
  #
  # @example Learn from a newly categorized transaction
  #   transaction.update!(category: food_category)
  #   PatternLearner.learn_from_transaction(transaction)
  #
  # @example Learn from multiple transactions
  #   PatternLearner.learn_from_transactions(transactions)
  #
  class PatternLearner
    # Learn categorization pattern from a single transaction
    #
    # Creates or updates a CategorizationPattern based on the transaction's
    # merchant name and assigned category.
    #
    # @param transaction [Transaction] The categorized transaction
    # @param source [Symbol] The enrichment source (:user, :rule, etc.)
    # @return [CategorizationPattern, nil] The created/updated pattern, or nil if skipped
    def self.learn_from_transaction(transaction, source: nil)
      new(transaction, source: source).learn
    end

    # Learn from multiple transactions in batch
    #
    # @param transactions [Array<Transaction>] Categorized transactions
    # @return [Integer] Number of patterns created/updated
    def self.learn_from_transactions(transactions)
      count = 0

      transactions.each do |transaction|
        pattern = learn_from_transaction(transaction)
        count += 1 if pattern
      end

      count
    end

    attr_reader :transaction, :source

    # Initialize pattern learner
    #
    # @param transaction [Transaction] The transaction to learn from
    # @param source [Symbol] Enrichment source (optional, detected from transaction)
    def initialize(transaction, source: nil)
      @transaction = transaction
      @source = source || detect_categorization_source
    end

    # Learn pattern from transaction
    #
    # @return [CategorizationPattern, nil] Created/updated pattern, or nil if skipped
    def learn
      return nil unless should_learn?

      merchant_name = extract_merchant_name
      return nil if merchant_name.blank?

      family = transaction.account.family
      category = transaction.category

      # Find or create pattern
      pattern = find_or_create_pattern(family, category, merchant_name)

      # Update pattern statistics
      pattern.record_match!

      pattern
    end

    private

    # Check if we should learn from this transaction
    #
    # Learning criteria:
    # - Transaction has a category assigned
    # - Categorization source is user or rule (not AI)
    # - Transaction has identifiable merchant or name
    #
    # @return [Boolean]
    def should_learn?
      return false if transaction.category_id.nil?

      # Only learn from high-quality categorization sources
      return false unless learning_source?

      # Must have merchant or transaction name for pattern matching
      merchant_name = extract_merchant_name
      merchant_name.present?
    end

    # Check if categorization source is suitable for learning
    #
    # @return [Boolean]
    def learning_source?
      return true if source == :user || source == :rule

      # If source not explicitly provided, check enrichment history
      if source.nil?
        enrichments = transaction.data_enrichments.where(attribute_name: "category_id")
        return true if enrichments.any? { |e| e.source.in?(["user", "rule"]) }
      end

      false
    end

    # Detect categorization source from transaction enrichment history
    #
    # @return [Symbol, nil]
    def detect_categorization_source
      enrichment = transaction.data_enrichments
        .where(attribute_name: "category_id")
        .order(created_at: :desc)
        .first

      enrichment&.source&.to_sym
    end

    # Extract merchant name for pattern matching
    #
    # Priority:
    # 1. Merchant name (if merchant assigned)
    # 2. Transaction name (fallback)
    #
    # @return [String, nil]
    def extract_merchant_name
      if transaction.merchant.present?
        transaction.merchant.name
      else
        transaction.name
      end
    end

    # Find or create categorization pattern
    #
    # @param family [Family]
    # @param category [Category]
    # @param merchant_name [String]
    # @return [CategorizationPattern]
    def find_or_create_pattern(family, category, merchant_name)
      normalized_name = CategorizationPattern.normalize_merchant_name(merchant_name)

      pattern = family.categorization_patterns.find_or_initialize_by(
        merchant_name_normalized: normalized_name,
        category: category
      )

      if pattern.new_record?
        pattern.merchant_name = merchant_name
        pattern.match_count = 1
        pattern.last_matched_at = Time.current
        pattern.recalculate_confidence!
        pattern.save!
      end

      pattern
    end
  end
  ```

- [ ] Add callback to Transaction model in `app/models/transaction.rb`
  ```ruby
  # Add to Transaction model

  # Learn categorization pattern after category is set
  after_commit :learn_categorization_pattern, on: [:create, :update], if: :should_learn_pattern?

  private

  def should_learn_pattern?
    # Only learn if category was just set or changed
    return false unless saved_change_to_category_id?
    return false if category_id.nil?

    # Check if this was a user or rule categorization
    enrichment = data_enrichments.where(attribute_name: "category_id").last
    enrichment&.source&.in?(["user", "rule"])
  end

  def learn_categorization_pattern
    PatternLearner.learn_from_transaction(self)
  end
  ```

- [ ] Update `SetTransactionCategory` rule action in `app/models/rule/action_executor/set_transaction_category.rb`
  ```ruby
  # Add to existing execute method, after enrichment

  def execute(transaction)
    return unless transaction.enrichable?(:category_id)

    transaction.enrich_attribute(:category_id, category.id, source: :rule)

    # Learn pattern from rule categorization
    PatternLearner.learn_from_transaction(transaction, source: :rule)
  end
  ```

- [ ] Write comprehensive tests in `test/models/pattern_learner_test.rb`
  ```ruby
  require "test_helper"

  class PatternLearnerTest < ActiveSupport::TestCase
    setup do
      @family = families(:dylan_family)
      @account = @family.accounts.first
      @category = categories(:food_and_drink)
    end

    test "learns pattern from user categorization" do
      transaction = create_transaction(
        merchant_name: "STARBUCKS #123",
        category: @category
      )

      # Mark as user categorization
      transaction.data_enrichments.create!(
        attribute_name: "category_id",
        value: @category.id,
        source: :user
      )

      assert_difference "CategorizationPattern.count", 1 do
        PatternLearner.learn_from_transaction(transaction, source: :user)
      end

      pattern = CategorizationPattern.last
      assert_equal @family, pattern.family
      assert_equal @category, pattern.category
      assert_equal "starbucks", pattern.merchant_name_normalized
      assert_equal 1, pattern.match_count
      assert pattern.confidence_score.present?
    end

    test "updates existing pattern when same merchant categorized again" do
      # Create initial pattern
      pattern = CategorizationPattern.create!(
        family: @family,
        category: @category,
        merchant_name: "STARBUCKS #123",
        merchant_name_normalized: "starbucks",
        match_count: 5,
        last_matched_at: 10.days.ago
      )

      original_confidence = pattern.confidence_score

      transaction = create_transaction(
        merchant_name: "STARBUCKS #456",  # Different store number
        category: @category
      )

      assert_no_difference "CategorizationPattern.count" do
        PatternLearner.learn_from_transaction(transaction, source: :user)
      end

      pattern.reload
      assert_equal 6, pattern.match_count
      assert pattern.last_matched_at > 1.minute.ago
      assert pattern.confidence_score > original_confidence  # Higher due to recency
    end

    test "does not learn from AI categorizations" do
      transaction = create_transaction(
        merchant_name: "TARGET",
        category: @category
      )

      transaction.data_enrichments.create!(
        attribute_name: "category_id",
        value: @category.id,
        source: :ai
      )

      assert_no_difference "CategorizationPattern.count" do
        PatternLearner.learn_from_transaction(transaction, source: :ai)
      end
    end

    test "does not learn from uncategorized transactions" do
      transaction = create_transaction(
        merchant_name: "ACME CORP",
        category: nil
      )

      assert_no_difference "CategorizationPattern.count" do
        PatternLearner.learn_from_transaction(transaction)
      end
    end

    test "learns from rule-based categorizations" do
      transaction = create_transaction(
        merchant_name: "WHOLE FOODS",
        category: @category
      )

      assert_difference "CategorizationPattern.count", 1 do
        PatternLearner.learn_from_transaction(transaction, source: :rule)
      end
    end

    test "normalizes merchant names correctly" do
      transaction = create_transaction(
        merchant_name: "McDonald's Restaurant #1234",
        category: @category
      )

      PatternLearner.learn_from_transaction(transaction, source: :user)

      pattern = CategorizationPattern.last
      # Should remove special chars, numbers, and normalize
      assert_equal "mcdonald s restaurant", pattern.merchant_name_normalized
    end

    test "uses transaction name if no merchant" do
      transaction = create_transaction(
        merchant: nil,
        name: "Coffee at Local Shop",
        category: @category
      )

      assert_difference "CategorizationPattern.count", 1 do
        PatternLearner.learn_from_transaction(transaction, source: :user)
      end

      pattern = CategorizationPattern.last
      assert_equal "coffee at local shop", pattern.merchant_name_normalized
    end

    test "batch learning from multiple transactions" do
      transactions = 3.times.map do |i|
        create_transaction(
          merchant_name: "TRADER JOES ##{i}",
          category: @category
        )
      end

      count = PatternLearner.learn_from_transactions(transactions)
      assert_equal 3, count

      # Should create single pattern for all variants
      pattern = CategorizationPattern.find_by(merchant_name_normalized: "trader joes")
      assert_equal 3, pattern.match_count
    end

    private

    def create_transaction(merchant_name: nil, merchant: nil, name: "Test Transaction", category: nil)
      merchant_obj = merchant || create_merchant(merchant_name) if merchant_name

      Transaction.create!(
        account: @account,
        amount: Money.new(1000, "USD"),
        date: Date.current,
        name: name,
        merchant: merchant_obj,
        category: category,
        kind: :standard
      )
    end

    def create_merchant(name)
      FamilyMerchant.create!(
        family: @family,
        name: name
      )
    end
  end
  ```

- [ ] Add DataEnrichment source enum value
  ```ruby
  # In app/models/data_enrichment.rb, add to enum:
  enum :source, {
    rule: "rule",
    plaid: "plaid",
    simplefin: "simplefin",
    lunchflow: "lunchflow",
    synth: "synth",
    ai: "ai",
    enable_banking: "enable_banking",
    pattern_match: "pattern_match",  # NEW
    user: "user"
  }, validate: true
  ```

### 4.3 Phase 3: Jaro-Winkler Similarity Matching

**Justification:** Implements spec section 3.3 (String Similarity Algorithm). Fuzzy matching for merchant name variations.

**Tasks:**

- [ ] Create `StringSimilarity` module in `app/models/string_similarity.rb`
  ```ruby
  # frozen_string_literal: true

  # String similarity algorithms for fuzzy matching
  module StringSimilarity
    # Calculate similarity between two strings
    #
    # @param str1 [String] First string
    # @param str2 [String] Second string
    # @param algorithm [Symbol] Algorithm to use (:jaro_winkler, :jaro)
    # @return [Float] Similarity score (0.0 to 1.0)
    def self.similarity(str1, str2, algorithm: :jaro_winkler)
      return 1.0 if str1 == str2
      return 0.0 if str1.blank? || str2.blank?

      case algorithm
      when :jaro_winkler
        JaroWinkler.similarity(str1, str2)
      when :jaro
        Jaro.similarity(str1, str2)
      else
        raise ArgumentError, "Unknown algorithm: #{algorithm}"
      end
    end
  end
  ```

- [ ] Create `JaroWinkler` calculator in `app/models/string_similarity/jaro_winkler.rb`
  ```ruby
  # frozen_string_literal: true

  module StringSimilarity
    # Jaro-Winkler string similarity algorithm
    #
    # The Jaro-Winkler distance is a string metric measuring edit distance
    # between two sequences. It is a variant of the Jaro distance metric
    # with a prefix bonus for strings that match from the beginning.
    #
    # The algorithm is particularly effective for short strings like names
    # and is commonly used for record linkage and duplicate detection.
    #
    # @example Calculate similarity
    #   JaroWinkler.similarity("MARTHA", "MARHTA")
    #   # => 0.96
    #
    #   JaroWinkler.similarity("STARBUCKS", "Starbucks Coffee")
    #   # => 0.88
    #
    class JaroWinkler
      # Default scaling factor for prefix bonus
      # Standard Jaro-Winkler uses 0.1
      PREFIX_SCALE = 0.1

      # Maximum prefix length to consider
      # Standard Jaro-Winkler uses 4
      MAX_PREFIX_LENGTH = 4

      # Calculate Jaro-Winkler similarity between two strings
      #
      # Formula:
      #   jw = jaro + (prefix_length * prefix_scale * (1 - jaro))
      #
      # where:
      #   jaro = Jaro similarity (0.0 to 1.0)
      #   prefix_length = length of common prefix (max 4 chars)
      #   prefix_scale = 0.1 (weight for prefix bonus)
      #
      # @param str1 [String] First string to compare
      # @param str2 [String] Second string to compare
      # @param prefix_scale [Float] Scaling factor for prefix bonus (default: 0.1)
      # @return [Float] Similarity score between 0.0 (no match) and 1.0 (exact match)
      def self.similarity(str1, str2, prefix_scale: PREFIX_SCALE)
        new(str1, str2, prefix_scale: prefix_scale).similarity
      end

      attr_reader :str1, :str2, :prefix_scale

      # Initialize Jaro-Winkler calculator
      #
      # @param str1 [String] First string
      # @param str2 [String] Second string
      # @param prefix_scale [Float] Prefix scaling factor
      def initialize(str1, str2, prefix_scale: PREFIX_SCALE)
        @str1 = str1.to_s.downcase
        @str2 = str2.to_s.downcase
        @prefix_scale = prefix_scale
      end

      # Calculate similarity score
      #
      # @return [Float] Similarity score (0.0 to 1.0)
      def similarity
        return 1.0 if str1 == str2
        return 0.0 if str1.empty? || str2.empty?

        # Calculate base Jaro similarity
        jaro_sim = Jaro.similarity(str1, str2)

        # Calculate common prefix length (up to max)
        prefix_len = common_prefix_length

        # Apply Winkler prefix bonus
        jaro_sim + (prefix_len * prefix_scale * (1.0 - jaro_sim))
      end

      private

      # Calculate length of common prefix between strings
      #
      # @return [Integer] Prefix length (0 to MAX_PREFIX_LENGTH)
      def common_prefix_length
        max_len = [str1.length, str2.length, MAX_PREFIX_LENGTH].min
        prefix_len = 0

        max_len.times do |i|
          break if str1[i] != str2[i]
          prefix_len += 1
        end

        prefix_len
      end
    end
  end
  ```

- [ ] Create `Jaro` calculator in `app/models/string_similarity/jaro.rb`
  ```ruby
  # frozen_string_literal: true

  module StringSimilarity
    # Jaro string similarity algorithm
    #
    # The Jaro distance is a measure of similarity between two strings.
    # The higher the Jaro distance, the more similar the strings are.
    #
    # The algorithm considers:
    # - Number of matching characters
    # - Number of transpositions (characters in different order)
    #
    # Formula:
    #   jaro = (m/|s1| + m/|s2| + (m-t)/m) / 3
    #
    # where:
    #   m = number of matching characters
    #   t = number of transpositions / 2
    #   |s1|, |s2| = lengths of the two strings
    #
    # @example Calculate similarity
    #   Jaro.similarity("MARTHA", "MARHTA")
    #   # => 0.94
    #
    class Jaro
      # Calculate Jaro similarity between two strings
      #
      # @param str1 [String] First string
      # @param str2 [String] Second string
      # @return [Float] Similarity score (0.0 to 1.0)
      def self.similarity(str1, str2)
        new(str1, str2).similarity
      end

      attr_reader :str1, :str2

      def initialize(str1, str2)
        @str1 = str1.to_s.downcase
        @str2 = str2.to_s.downcase
      end

      # Calculate Jaro similarity
      #
      # @return [Float] Similarity score (0.0 to 1.0)
      def similarity
        return 1.0 if str1 == str2
        return 0.0 if str1.empty? || str2.empty?

        # Calculate match window
        match_distance = max_match_distance

        # Find matching characters
        matches1, matches2 = find_matches(match_distance)
        match_count = matches1.count(true)

        return 0.0 if match_count.zero?

        # Calculate transpositions
        transpositions = count_transpositions(matches1, matches2)

        # Jaro formula
        (
          (match_count.to_f / str1.length) +
          (match_count.to_f / str2.length) +
          ((match_count - transpositions).to_f / match_count)
        ) / 3.0
      end

      private

      # Maximum distance for character matching
      # Formula: max(|s1|, |s2|) / 2 - 1
      #
      # @return [Integer] Match distance
      def max_match_distance
        ([str1.length, str2.length].max / 2) - 1
      end

      # Find matching characters within match distance
      #
      # @param match_distance [Integer] Maximum distance for matches
      # @return [Array<Array<Boolean>>] [matches1, matches2] - boolean arrays indicating matches
      def find_matches(match_distance)
        matches1 = Array.new(str1.length, false)
        matches2 = Array.new(str2.length, false)

        str1.each_char.with_index do |c1, i|
          # Define search window
          start_idx = [0, i - match_distance].max
          end_idx = [str2.length - 1, i + match_distance].min

          # Search for match in window
          (start_idx..end_idx).each do |j|
            next if matches2[j]  # Already matched
            next unless str2[j] == c1  # Characters don't match

            # Found a match
            matches1[i] = true
            matches2[j] = true
            break
          end
        end

        [matches1, matches2]
      end

      # Count transpositions (matching characters in wrong order)
      #
      # @param matches1 [Array<Boolean>] Match flags for str1
      # @param matches2 [Array<Boolean>] Match flags for str2
      # @return [Integer] Number of transpositions
      def count_transpositions(matches1, matches2)
        transpositions = 0
        k = 0  # Index in matched characters of str2

        str1.each_char.with_index do |c, i|
          next unless matches1[i]  # Only check matched characters

          # Find next matched character in str2
          k += 1 while k < str2.length && !matches2[k]

          # If characters don't match, it's a transposition
          transpositions += 1 if str1[i] != str2[k]

          k += 1
        end

        transpositions / 2
      end
    end
  end
  ```

- [ ] Write comprehensive tests in `test/models/string_similarity/jaro_winkler_test.rb`
  ```ruby
  require "test_helper"

  module StringSimilarity
    class JaroWinklerTest < ActiveSupport::TestCase
      test "returns 1.0 for identical strings" do
        assert_equal 1.0, JaroWinkler.similarity("hello", "hello")
        assert_equal 1.0, JaroWinkler.similarity("STARBUCKS", "STARBUCKS")
      end

      test "returns 0.0 for completely different strings" do
        similarity = JaroWinkler.similarity("abc", "xyz")
        assert similarity < 0.5
      end

      test "handles case insensitivity" do
        similarity = JaroWinkler.similarity("STARBUCKS", "starbucks")
        assert_equal 1.0, similarity
      end

      test "calculates similarity for merchant name variations" do
        # STARBUCKS vs Starbucks Coffee
        similarity = JaroWinkler.similarity("STARBUCKS", "Starbucks Coffee")
        assert similarity > 0.80, "Expected high similarity for merchant variants"
        assert similarity < 1.0
      end

      test "handles transpositions" do
        # MARTHA vs MARHTA (transposition of TH)
        similarity = JaroWinkler.similarity("MARTHA", "MARHTA")
        assert similarity > 0.90, "Expected high similarity for transposition"
      end

      test "gives prefix bonus for matching starts" do
        # Jaro-Winkler should score higher than Jaro for common prefixes
        jaro = Jaro.similarity("starbucks store", "starbucks coffee")
        jaro_winkler = JaroWinkler.similarity("starbucks store", "starbucks coffee")

        assert jaro_winkler > jaro, "Jaro-Winkler should give prefix bonus"
      end

      test "handles empty strings" do
        assert_equal 0.0, JaroWinkler.similarity("", "hello")
        assert_equal 0.0, JaroWinkler.similarity("hello", "")
        assert_equal 0.0, JaroWinkler.similarity("", "")
      end

      test "real-world merchant matching examples" do
        test_cases = [
          ["SHELL OIL", "Shell Gas Station", 0.70],
          ["TARGET #1234", "Target Store", 0.75],
          ["MCDONALD'S", "McDonald's Restaurant", 0.85],
          ["WHOLE FOODS", "Whole Foods Market", 0.88],
          ["AMAZON.COM", "Amazon", 0.85]
        ]

        test_cases.each do |merchant1, merchant2, min_expected|
          similarity = JaroWinkler.similarity(merchant1, merchant2)
          assert similarity >= min_expected,
            "Expected #{merchant1} vs #{merchant2} to have similarity >= #{min_expected}, got #{similarity}"
        end
      end
    end
  end
  ```

- [ ] Write tests for Jaro algorithm in `test/models/string_similarity/jaro_test.rb`
  - Test identical strings return 1.0
  - Test empty strings return 0.0
  - Test known examples (MARTHA/MARHTA, etc.)
  - Test transposition counting
  - Test match distance calculation

### 4.4 Phase 4: Pattern Matching & Confidence Scoring

**Justification:** Implements spec sections 3.2, 3.4 (Pattern Matching, Confidence Scoring). Core matching engine for category suggestions.

**Tasks:**

- [ ] Create `CategorySuggestion` value object in `app/models/category_suggestion.rb`
  ```ruby
  # frozen_string_literal: true

  # Value object representing a category suggestion for a transaction
  #
  # Contains the suggested category, confidence score, and metadata
  # explaining the basis for the suggestion.
  #
  # @example High-confidence suggestion
  #   CategorySuggestion.new(
  #     category: food_category,
  #     confidence: 0.85,
  #     similarity: 0.92,
  #     pattern: categorization_pattern,
  #     match_type: :exact
  #   )
  #
  CategorySuggestion = Data.define(
    :category,      # Category object
    :confidence,    # Float (0.0 to 1.0) - overall confidence score
    :similarity,    # Float (0.0 to 1.0) - string similarity score
    :pattern,       # CategorizationPattern that matched
    :match_type     # Symbol (:exact, :fuzzy, :partial)
  ) do
    # Check if suggestion meets auto-categorization threshold
    #
    # @return [Boolean] True if confidence >= 75%
    def auto_categorizable?
      confidence >= 0.75
    end

    # Get confidence level for UI display
    #
    # @return [Symbol] :high, :medium, or :low
    def confidence_level
      return :high if confidence >= 0.85
      return :medium if confidence >= 0.75
      :low
    end

    # Get human-readable explanation of suggestion
    #
    # @return [String] Explanation text
    def explanation
      match_description = case match_type
      when :exact
        "exact match"
      when :fuzzy
        "similar match (#{(similarity * 100).round}% similar)"
      when :partial
        "partial match"
      else
        "match"
      end

      "Based on #{pattern.match_count} previous transactions (#{match_description})"
    end
  end
  ```

- [ ] Create `PatternMatcher` service in `app/models/pattern_matcher.rb`
  ```ruby
  # frozen_string_literal: true

  # Service for matching transactions to categorization patterns
  #
  # Uses historical transaction patterns and fuzzy string matching
  # to suggest categories for uncategorized transactions.
  #
  # Matching strategy:
  # 1. Exact merchant name match (normalized)
  # 2. Fuzzy merchant name match (Jaro-Winkler >= 0.80)
  # 3. Transaction name pattern match
  #
  # Confidence calculation:
  # - Base confidence from pattern statistics (frequency, recency)
  # - Adjusted by string similarity score
  # - Minimum 75% confidence for auto-categorization
  #
  # @example Find category suggestion
  #   matcher = PatternMatcher.new(transaction: transaction, family: family)
  #   suggestion = matcher.suggest
  #
  #   if suggestion && suggestion.auto_categorizable?
  #     transaction.update!(category: suggestion.category)
  #   end
  #
  # @example Get multiple suggestions
  #   suggestions = matcher.suggest_all(limit: 3)
  #   suggestions.each { |s| puts "#{s.category.name}: #{s.confidence}" }
  #
  class PatternMatcher
    # Minimum similarity threshold for fuzzy matching
    FUZZY_SIMILARITY_THRESHOLD = 0.80

    # Maximum number of suggestions to return
    DEFAULT_SUGGESTION_LIMIT = 5

    attr_reader :transaction, :family

    # Initialize pattern matcher
    #
    # @param transaction [Transaction] Transaction to find category for
    # @param family [Family] Family context for pattern lookup
    def initialize(transaction:, family:)
      @transaction = transaction
      @family = family
    end

    # Get best category suggestion
    #
    # Returns the highest confidence suggestion that meets the
    # auto-categorization threshold (>= 75%).
    #
    # @return [CategorySuggestion, nil] Best suggestion or nil if none found
    def suggest
      suggestions = suggest_all(limit: 1)
      suggestion = suggestions.first

      # Only return if meets threshold
      suggestion if suggestion&.auto_categorizable?
    end

    # Get multiple category suggestions
    #
    # Returns top N suggestions sorted by confidence (descending).
    # Includes suggestions below auto-categorization threshold for
    # display in UI suggestion lists.
    #
    # @param limit [Integer] Maximum number of suggestions (default: 5)
    # @return [Array<CategorySuggestion>] Array of suggestions
    def suggest_all(limit: DEFAULT_SUGGESTION_LIMIT)
      merchant_name = extract_merchant_name
      return [] if merchant_name.blank?

      # Find matching patterns
      exact_matches = find_exact_matches(merchant_name)
      fuzzy_matches = find_fuzzy_matches(merchant_name) if exact_matches.empty?

      matches = exact_matches.presence || fuzzy_matches || []

      # Build suggestions from matches
      suggestions = matches.map do |pattern, similarity|
        build_suggestion(pattern, similarity)
      end

      # Sort by confidence and limit
      suggestions
        .sort_by { |s| -s.confidence }
        .take(limit)
    end

    private

    # Extract merchant name from transaction
    #
    # Priority:
    # 1. Merchant name (if merchant assigned)
    # 2. Transaction name (fallback)
    #
    # @return [String, nil]
    def extract_merchant_name
      if transaction.merchant.present?
        transaction.merchant.name
      else
        transaction.name
      end
    end

    # Find patterns with exact normalized merchant name match
    #
    # @param merchant_name [String] Original merchant name
    # @return [Array<Array(CategorizationPattern, Float)>] Array of [pattern, similarity] tuples
    def find_exact_matches(merchant_name)
      normalized_name = CategorizationPattern.normalize_merchant_name(merchant_name)

      patterns = family.categorization_patterns
        .for_merchant(normalized_name)
        .ordered_by_confidence

      # Exact match = 1.0 similarity
      patterns.map { |pattern| [pattern, 1.0] }
    end

    # Find patterns with fuzzy merchant name match
    #
    # Uses Jaro-Winkler algorithm to find similar merchant names.
    # Only includes matches with similarity >= 80%.
    #
    # @param merchant_name [String] Original merchant name
    # @return [Array<Array(CategorizationPattern, Float)>] Array of [pattern, similarity] tuples
    def find_fuzzy_matches(merchant_name)
      normalized_name = CategorizationPattern.normalize_merchant_name(merchant_name)

      # Get all patterns for this family (can be optimized with better indexing)
      all_patterns = family.categorization_patterns.ordered_by_confidence

      fuzzy_matches = all_patterns.filter_map do |pattern|
        similarity = StringSimilarity.similarity(
          normalized_name,
          pattern.merchant_name_normalized,
          algorithm: :jaro_winkler
        )

        # Only include if similarity meets threshold
        next unless similarity >= FUZZY_SIMILARITY_THRESHOLD

        [pattern, similarity]
      end

      # Sort by similarity (descending)
      fuzzy_matches.sort_by { |(_, similarity)| -similarity }
    end

    # Build category suggestion from pattern and similarity
    #
    # Calculates final confidence score by combining:
    # - Pattern's base confidence (from frequency/recency)
    # - String similarity score
    #
    # @param pattern [CategorizationPattern] Matching pattern
    # @param similarity [Float] String similarity score (0.0 to 1.0)
    # @return [CategorySuggestion]
    def build_suggestion(pattern, similarity)
      # Calculate final confidence
      base_confidence = pattern.confidence_score || 0.5
      final_confidence = calculate_final_confidence(base_confidence, similarity)

      # Determine match type
      match_type = if similarity >= 0.95
        :exact
      elsif similarity >= FUZZY_SIMILARITY_THRESHOLD
        :fuzzy
      else
        :partial
      end

      CategorySuggestion.new(
        category: pattern.category,
        confidence: final_confidence,
        similarity: similarity,
        pattern: pattern,
        match_type: match_type
      )
    end

    # Calculate final confidence score
    #
    # Combines pattern's base confidence with string similarity.
    #
    # Formula:
    #   final = base_confidence * similarity_multiplier
    #
    # Where similarity_multiplier boosts confidence for exact matches
    # and reduces it for fuzzy matches.
    #
    # @param base_confidence [Float] Pattern's confidence score
    # @param similarity [Float] String similarity score
    # @return [Float] Final confidence (0.0 to 1.0)
    def calculate_final_confidence(base_confidence, similarity)
      # Similarity acts as a multiplier
      # - Exact match (1.0): full base confidence
      # - Fuzzy match (0.8): reduced confidence
      final = base_confidence * similarity

      # Cap at 1.0
      [final, 1.0].min
    end
  end
  ```

- [ ] Write comprehensive tests in `test/models/pattern_matcher_test.rb`
  ```ruby
  require "test_helper"

  class PatternMatcherTest < ActiveSupport::TestCase
    setup do
      @family = families(:dylan_family)
      @account = @family.accounts.first
      @food_category = categories(:food_and_drink)
      @gas_category = categories(:transportation)

      # Create patterns
      @starbucks_pattern = CategorizationPattern.create!(
        family: @family,
        category: @food_category,
        merchant_name: "STARBUCKS STORE #1234",
        merchant_name_normalized: "starbucks",
        match_count: 15,
        confidence_score: 0.88,
        last_matched_at: 2.days.ago
      )

      @shell_pattern = CategorizationPattern.create!(
        family: @family,
        category: @gas_category,
        merchant_name: "SHELL OIL 12345",
        merchant_name_normalized: "shell oil",
        match_count: 8,
        confidence_score: 0.75,
        last_matched_at: 5.days.ago
      )
    end

    test "finds exact match for identical merchant name" do
      transaction = create_transaction(merchant_name: "STARBUCKS STORE #5678")
      matcher = PatternMatcher.new(transaction: transaction, family: @family)

      suggestion = matcher.suggest

      assert suggestion.present?
      assert_equal @food_category, suggestion.category
      assert_equal :exact, suggestion.match_type
      assert suggestion.confidence >= 0.75
      assert_equal @starbucks_pattern, suggestion.pattern
    end

    test "finds fuzzy match for similar merchant name" do
      # "Starbucks Coffee" is similar to "STARBUCKS" pattern
      transaction = create_transaction(merchant_name: "Starbucks Coffee Shop")
      matcher = PatternMatcher.new(transaction: transaction, family: @family)

      suggestion = matcher.suggest

      assert suggestion.present?
      assert_equal @food_category, suggestion.category
      assert_equal :fuzzy, suggestion.match_type
      assert suggestion.similarity >= 0.80
    end

    test "returns nil if no patterns meet confidence threshold" do
      # Create weak pattern (low confidence)
      weak_pattern = CategorizationPattern.create!(
        family: @family,
        category: @food_category,
        merchant_name: "RANDOM PLACE",
        merchant_name_normalized: "random place",
        match_count: 1,
        confidence_score: 0.30,
        last_matched_at: 6.months.ago
      )

      transaction = create_transaction(merchant_name: "RANDOM PLACE")
      matcher = PatternMatcher.new(transaction: transaction, family: @family)

      suggestion = matcher.suggest

      # Should be nil because confidence < 75%
      assert_nil suggestion
    end

    test "suggest_all returns multiple suggestions sorted by confidence" do
      # Create multiple patterns for same merchant (different categories)
      alt_pattern = CategorizationPattern.create!(
        family: @family,
        category: @gas_category,
        merchant_name: "STARBUCKS",
        merchant_name_normalized: "starbucks",
        match_count: 3,
        confidence_score: 0.60,
        last_matched_at: 10.days.ago
      )

      transaction = create_transaction(merchant_name: "STARBUCKS")
      matcher = PatternMatcher.new(transaction: transaction, family: @family)

      suggestions = matcher.suggest_all(limit: 5)

      assert suggestions.size >= 1
      # Should be sorted by confidence
      assert_equal suggestions, suggestions.sort_by { |s| -s.confidence }
      # Highest confidence should be food category
      assert_equal @food_category, suggestions.first.category
    end

    test "handles transaction without merchant using transaction name" do
      transaction = create_transaction(
        merchant: nil,
        name: "STARBUCKS COFFEE"
      )
      matcher = PatternMatcher.new(transaction: transaction, family: @family)

      suggestion = matcher.suggest

      assert suggestion.present?
      assert_equal @food_category, suggestion.category
    end

    test "returns empty array if no merchant or transaction name" do
      transaction = create_transaction(
        merchant: nil,
        name: nil
      )
      matcher = PatternMatcher.new(transaction: transaction, family: @family)

      suggestions = matcher.suggest_all

      assert_empty suggestions
    end

    test "confidence calculation combines pattern confidence and similarity" do
      transaction = create_transaction(merchant_name: "Starbucks Coffee")
      matcher = PatternMatcher.new(transaction: transaction, family: @family)

      suggestion = matcher.suggest

      # Confidence should be pattern confidence * similarity
      # Pattern: 0.88, Similarity should be ~0.85-0.95 for "starbucks" vs "starbucks coffee"
      assert suggestion.confidence <= @starbucks_pattern.confidence_score
      assert suggestion.confidence > 0.70
    end

    test "exact matches have higher confidence than fuzzy matches" do
      exact_transaction = create_transaction(merchant_name: "STARBUCKS")
      fuzzy_transaction = create_transaction(merchant_name: "Starbucks Coffee House")

      exact_suggestion = PatternMatcher.new(
        transaction: exact_transaction,
        family: @family
      ).suggest

      fuzzy_suggestion = PatternMatcher.new(
        transaction: fuzzy_transaction,
        family: @family
      ).suggest

      assert exact_suggestion.confidence > fuzzy_suggestion.confidence
    end

    test "does not match if similarity below threshold" do
      # Completely different merchant
      transaction = create_transaction(merchant_name: "WALMART")
      matcher = PatternMatcher.new(transaction: transaction, family: @family)

      suggestion = matcher.suggest

      assert_nil suggestion
    end

    private

    def create_transaction(merchant_name: nil, merchant: nil, name: "Test Transaction")
      merchant_obj = merchant || create_merchant(merchant_name) if merchant_name

      Transaction.create!(
        account: @account,
        amount: Money.new(1000, "USD"),
        date: Date.current,
        name: name,
        merchant: merchant_obj,
        kind: :standard
      )
    end

    def create_merchant(name)
      FamilyMerchant.create!(
        family: @family,
        name: name
      )
    end
  end
  ```

- [ ] Write tests for CategorySuggestion in `test/models/category_suggestion_test.rb`
  - Test `auto_categorizable?` threshold
  - Test `confidence_level` categorization
  - Test `explanation` message formatting

### 4.5 Phase 5: Auto-Categorization Integration

**Justification:** Implements spec section 3.5 (Integration Architecture). Integrates pattern matching into transaction import flow.

**Tasks:**

- [ ] Create `AutoCategorizeFromPatternJob` in `app/jobs/auto_categorize_from_pattern_job.rb`
  ```ruby
  # frozen_string_literal: true

  # Background job for pattern-based auto-categorization
  #
  # Applies category suggestions from learned patterns to uncategorized
  # transactions. Only applies if confidence >= 75%.
  #
  # @example Categorize a single transaction
  #   AutoCategorizeFromPatternJob.perform_later(transaction)
  #
  # @example Categorize multiple transactions
  #   transactions.each { |t| AutoCategorizeFromPatternJob.perform_later(t) }
  #
  class AutoCategorizeFromPatternJob < ApplicationJob
    queue_as :default

    # Categorize transaction using pattern matching
    #
    # @param transaction [Transaction] Transaction to categorize
    def perform(transaction)
      return if transaction.category_id.present?  # Already categorized
      return unless transaction.enrichable?(:category_id)  # Locked by user

      family = transaction.account.family
      matcher = PatternMatcher.new(transaction: transaction, family: family)
      suggestion = matcher.suggest

      return unless suggestion  # No high-confidence match

      # Apply categorization
      transaction.enrich_attribute(
        :category_id,
        suggestion.category.id,
        source: :pattern_match,
        metadata: {
          confidence: suggestion.confidence.round(2),
          similarity: suggestion.similarity.round(2),
          pattern_id: suggestion.pattern.id,
          match_type: suggestion.match_type
        }
      )

      # Update pattern statistics
      suggestion.pattern.record_match!
    end
  end
  ```

- [ ] Integrate into transaction import in `app/models/account/provider_import_adapter.rb`
  ```ruby
  # Add after rules execution, before AI categorization
  # In import_transaction method or similar

  # Pattern-based auto-categorization (after rules, before AI)
  if transaction.category_id.nil? && transaction.enrichable?(:category_id)
    matcher = PatternMatcher.new(transaction: transaction, family: family)
    suggestion = matcher.suggest

    if suggestion
      transaction.enrich_attribute(
        :category_id,
        suggestion.category.id,
        source: :pattern_match,
        metadata: {
          confidence: suggestion.confidence.round(2),
          similarity: suggestion.similarity.round(2),
          pattern_id: suggestion.pattern.id
        }
      )

      # Update pattern match count
      suggestion.pattern.record_match!
    end
  end
  ```

- [ ] Add pattern cleanup job in `app/jobs/prune_categorization_patterns_job.rb`
  ```ruby
  # frozen_string_literal: true

  # Periodic job to prune stale categorization patterns
  #
  # Removes patterns that:
  # - Have not been matched in 6+ months
  # - Have fewer than 5 matches total
  # - Have very low confidence (< 30%)
  #
  # Runs daily via sidekiq-cron to keep pattern table clean.
  #
  class PruneCategorizationPatternsJob < ApplicationJob
    queue_as :scheduled

    def perform
      # Remove stale, low-usage patterns
      stale_count = CategorizationPattern.stale.low_usage.delete_all

      # Remove very low confidence patterns
      low_confidence_count = CategorizationPattern
        .where("confidence_score < ?", 0.30)
        .delete_all

      Rails.logger.info(
        "Pruned #{stale_count + low_confidence_count} categorization patterns"
      )
    end
  end
  ```

- [ ] Add to sidekiq-cron schedule in `config/schedule.yml`
  ```yaml
  prune_categorization_patterns:
    cron: "0 3 * * *"  # 3:00 AM daily
    class: "PruneCategorizationPatternsJob"
    queue: "scheduled"
  ```

- [ ] Write integration tests in `test/jobs/auto_categorize_from_pattern_job_test.rb`
  - Test categorizes uncategorized transaction with high-confidence match
  - Test skips already categorized transactions
  - Test respects locked attributes
  - Test updates pattern match count
  - Test stores metadata in enrichment

- [ ] Write tests for pruning job in `test/jobs/prune_categorization_patterns_job_test.rb`
  - Test removes stale patterns
  - Test removes low-confidence patterns
  - Test keeps recent, high-quality patterns

### 4.6 Phase 6: Bulk Categorization UI

**Justification:** Implements spec section 3.6 (UI Components - Bulk Categorization). User interface for reviewing and applying category suggestions.

**Tasks:**

- [ ] Add routes in `config/routes.rb`
  ```ruby
  resources :transactions do
    collection do
      get :bulk_categorize
      post :apply_bulk_categorization
    end
  end
  ```

- [ ] Add bulk categorization actions to TransactionsController
  ```ruby
  # Add to app/controllers/transactions_controller.rb

  # GET /transactions/bulk_categorize
  def bulk_categorize
    @uncategorized_transactions = Current.family.transactions
      .joins(:entry)
      .where(category_id: nil, kind: ["standard", "loan_payment"])
      .where.not(entries: { excluded: true })
      .includes(:account, :merchant, :category)
      .order("entries.date DESC")
      .limit(100)  # Limit for performance

    # Generate suggestions for each transaction
    @suggestions = generate_bulk_suggestions(@uncategorized_transactions)
  end

  # POST /transactions/apply_bulk_categorization
  def apply_bulk_categorization
    transaction_ids = params[:transaction_ids] || []

    if transaction_ids.any?
      ApplyBulkCategorizationJob.perform_later(
        transaction_ids: transaction_ids,
        family_id: Current.family.id
      )

      redirect_to bulk_categorize_transactions_path,
        notice: t(".success", count: transaction_ids.size)
    else
      redirect_to bulk_categorize_transactions_path,
        alert: t(".no_selection")
    end
  end

  private

  def generate_bulk_suggestions(transactions)
    suggestions = {}

    transactions.each do |transaction|
      matcher = PatternMatcher.new(
        transaction: transaction,
        family: Current.family
      )

      # Get top suggestion
      suggestion = matcher.suggest_all(limit: 1).first
      suggestions[transaction.id] = suggestion if suggestion
    end

    suggestions
  end
  ```

- [ ] Create bulk categorization view in `app/views/transactions/bulk_categorize.html.erb`
  ```erb
  <div class="bulk-categorization-page">
    <div class="page-header mb-6">
      <h1 class="text-2xl font-bold text-primary">
        <%= t(".heading") %>
      </h1>
      <p class="text-sm text-tertiary">
        <%= t(".description") %>
      </p>
    </div>

    <%= form_with url: apply_bulk_categorization_transactions_path, method: :post do |form| %>
      <div class="actions-bar mb-4 flex items-center gap-4">
        <%= form.button t(".apply_selected"), class: "btn btn-primary" %>

        <button type="button"
                data-action="click->bulk-categorize#selectHighConfidence"
                class="btn btn-secondary">
          <%= t(".select_high_confidence") %>
        </button>

        <span class="text-sm text-tertiary">
          <%= t(".uncategorized_count", count: @uncategorized_transactions.size) %>
        </span>
      </div>

      <div class="transactions-table"
           data-controller="bulk-categorize">
        <table class="w-full">
          <thead>
            <tr class="border-b border-primary">
              <th class="p-2">
                <input type="checkbox" data-action="change->bulk-categorize#toggleAll">
              </th>
              <th class="p-2 text-left"><%= t(".date") %></th>
              <th class="p-2 text-left"><%= t(".merchant") %></th>
              <th class="p-2 text-right"><%= t(".amount") %></th>
              <th class="p-2 text-left"><%= t(".suggested_category") %></th>
              <th class="p-2"></th>
            </tr>
          </thead>
          <tbody>
            <% @uncategorized_transactions.each do |transaction| %>
              <% suggestion = @suggestions[transaction.id] %>

              <tr class="border-b border-primary hover:bg-surface-inset">
                <td class="p-2">
                  <% if suggestion&.auto_categorizable? %>
                    <%= check_box_tag "transaction_ids[]",
                                      transaction.id,
                                      false,
                                      data: {
                                        bulk_categorize_target: "checkbox",
                                        confidence: suggestion.confidence
                                      },
                                      class: "form-checkbox" %>
                  <% end %>
                </td>

                <td class="p-2 text-sm">
                  <%= l(transaction.date, format: :short) %>
                </td>

                <td class="p-2">
                  <div class="text-sm font-medium text-primary">
                    <%= transaction.merchant&.name || transaction.name %>
                  </div>
                  <div class="text-xs text-tertiary">
                    <%= transaction.account.name %>
                  </div>
                </td>

                <td class="p-2 text-right font-mono text-sm">
                  <%= transaction.amount.format %>
                </td>

                <td class="p-2">
                  <% if suggestion %>
                    <div class="flex items-center gap-2">
                      <%= render "suggestion_badge", suggestion: suggestion %>

                      <span class="text-sm text-primary">
                        <%= suggestion.category.name %>
                      </span>

                      <span class="text-xs text-tertiary"
                            title="<%= suggestion.explanation %>">
                        <%= icon("info", class: "w-3 h-3") %>
                      </span>
                    </div>
                  <% else %>
                    <span class="text-sm text-tertiary">
                      <%= t(".no_suggestion") %>
                    </span>
                  <% end %>
                </td>

                <td class="p-2">
                  <%= link_to t(".edit"),
                              edit_transaction_path(transaction),
                              class: "text-xs text-link hover:underline" %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>

        <% if @uncategorized_transactions.empty? %>
          <div class="empty-state text-center py-12">
            <%= icon("check-circle", class: "w-12 h-12 text-success mx-auto mb-4") %>
            <p class="text-primary"><%= t(".all_categorized") %></p>
          </div>
        <% end %>
      </div>
    <% end %>
  </div>
  ```

- [ ] Create suggestion badge partial in `app/views/transactions/_suggestion_badge.html.erb`
  ```erb
  <%
    badge_class = case suggestion.confidence_level
    when :high
      "bg-success/10 text-success border-success"
    when :medium
      "bg-warning/10 text-warning border-warning"
    else
      "bg-tertiary/10 text-tertiary border-tertiary"
    end
  %>

  <span class="inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs border <%= badge_class %>">
    <%= (suggestion.confidence * 100).round %>%
  </span>
  ```

- [ ] Create Stimulus controller in `app/javascript/controllers/bulk_categorize_controller.js`
  ```javascript
  import { Controller } from "@hotwired/stimulus"

  export default class extends Controller {
    static targets = ["checkbox"]

    toggleAll(event) {
      const checked = event.target.checked

      this.checkboxTargets.forEach(checkbox => {
        checkbox.checked = checked
      })
    }

    selectHighConfidence() {
      this.checkboxTargets.forEach(checkbox => {
        const confidence = parseFloat(checkbox.dataset.confidence)
        checkbox.checked = confidence >= 0.85
      })
    }
  }
  ```

- [ ] Create background job in `app/jobs/apply_bulk_categorization_job.rb`
  ```ruby
  class ApplyBulkCategorizationJob < ApplicationJob
    queue_as :default

    def perform(transaction_ids:, family_id:)
      family = Family.find(family_id)
      transactions = family.transactions.where(id: transaction_ids)

      transactions.each do |transaction|
        AutoCategorizeFromPatternJob.perform_now(transaction)
      end
    end
  end
  ```

- [ ] Add localization in `config/locales/views/transactions/bulk_categorize.en.yml`
  ```yaml
  en:
    transactions:
      bulk_categorize:
        heading: "Bulk Categorization"
        description: "Review and apply category suggestions for uncategorized transactions"
        apply_selected: "Apply Selected"
        select_high_confidence: "Select High Confidence (≥85%)"
        uncategorized_count: "%{count} uncategorized transactions"
        date: "Date"
        merchant: "Merchant/Description"
        amount: "Amount"
        suggested_category: "Suggested Category"
        edit: "Edit"
        no_suggestion: "No suggestion"
        all_categorized: "All transactions are categorized!"

      apply_bulk_categorization:
        success: "Categorization applied to %{count} transactions"
        no_selection: "Please select transactions to categorize"
  ```

- [ ] Add navigation link
  - Add "Bulk Categorize" link in transactions navigation
  - Show badge with count of uncategorized transactions (if > 0)

### 4.7 Phase 7: Transaction Form Suggestions

**Justification:** Implements spec section 3.6 (UI Components - Form Suggestions). Inline suggestions in transaction edit form.

**Tasks:**

- [ ] Add suggestions to transaction form in `app/views/transactions/_form.html.erb`
  ```erb
  <%# Add after category field label, before category select %>

  <% if transaction.new_record? || transaction.category_id.nil? %>
    <% suggestions = generate_category_suggestions(transaction) %>

    <% if suggestions.any? %>
      <div class="category-suggestions mb-2 p-3 bg-surface-inset rounded-lg"
           data-controller="category-suggestions">
        <p class="text-xs font-semibold text-tertiary mb-2">
          <%= t(".suggested_categories") %>
        </p>

        <div class="space-y-1">
          <% suggestions.take(3).each do |suggestion| %>
            <button type="button"
                    data-action="click->category-suggestions#select"
                    data-category-id="<%= suggestion.category.id %>"
                    data-category-name="<%= suggestion.category.name %>"
                    class="w-full text-left p-2 rounded hover:bg-surface transition-colors">
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-2">
                  <span class="text-sm font-medium text-primary">
                    <%= suggestion.category.name %>
                  </span>

                  <%= render "transactions/suggestion_badge", suggestion: suggestion %>
                </div>

                <%= icon("chevron-right", class: "w-4 h-4 text-tertiary") %>
              </div>

              <p class="text-xs text-tertiary mt-0.5">
                <%= suggestion.explanation %>
              </p>
            </button>
          <% end %>
        </div>
      </div>
    <% end %>
  <% end %>

  <%# Original category select field below %>
  ```

- [ ] Create helper method in `app/helpers/transactions_helper.rb`
  ```ruby
  # Generate category suggestions for transaction form
  #
  # @param transaction [Transaction]
  # @return [Array<CategorySuggestion>]
  def generate_category_suggestions(transaction)
    return [] unless transaction.account

    family = transaction.account.family
    matcher = PatternMatcher.new(transaction: transaction, family: family)
    matcher.suggest_all(limit: 3)
  end
  ```

- [ ] Create Stimulus controller in `app/javascript/controllers/category_suggestions_controller.js`
  ```javascript
  import { Controller } from "@hotwired/stimulus"

  export default class extends Controller {
    select(event) {
      const categoryId = event.currentTarget.dataset.categoryId
      const categoryName = event.currentTarget.dataset.categoryName

      // Find category select field and update it
      const categorySelect = document.querySelector('select[name="transaction[category_id]"]')

      if (categorySelect) {
        categorySelect.value = categoryId

        // Trigger change event for any listeners
        categorySelect.dispatchEvent(new Event('change', { bubbles: true }))

        // Visual feedback
        this.element.classList.add('opacity-50')

        // Show confirmation
        this.showConfirmation(categoryName)
      }
    }

    showConfirmation(categoryName) {
      // Simple confirmation (can be enhanced with toast notifications)
      const message = document.createElement('div')
      message.className = 'text-xs text-success mt-2'
      message.textContent = `Category set to: ${categoryName}`

      this.element.appendChild(message)

      setTimeout(() => message.remove(), 3000)
    }
  }
  ```

- [ ] Add localization
  ```yaml
  en:
    transactions:
      form:
        suggested_categories: "Suggested categories based on similar transactions"
  ```

### 4.8 Phase 8: Testing & Documentation

**Justification:** Validation and documentation. Ensures feature works end-to-end.

**Tasks:**

- [ ] Write system test in `test/system/smart_categorization_test.rb`
  ```ruby
  require "application_system_test_case"

  class SmartCategorizationTest < ApplicationSystemTestCase
    setup do
      sign_in users(:dylan)
      @family = families(:dylan_family)
      @category = categories(:food_and_drink)

      # Create pattern
      @pattern = CategorizationPattern.create!(
        family: @family,
        category: @category,
        merchant_name: "STARBUCKS",
        merchant_name_normalized: "starbucks",
        match_count: 10,
        confidence_score: 0.85,
        last_matched_at: 1.day.ago
      )
    end

    test "bulk categorization page shows suggestions" do
      # Create uncategorized transaction
      account = @family.accounts.first
      transaction = Transaction.create!(
        account: account,
        amount: Money.new(500, "USD"),
        date: Date.current,
        name: "STARBUCKS #123",
        kind: :standard
      )

      visit bulk_categorize_transactions_path

      assert_text "Bulk Categorization"
      assert_text "STARBUCKS"
      assert_text @category.name
      assert_text "85%"  # Confidence badge
    end

    test "applying bulk categorization" do
      # Create uncategorized transaction
      account = @family.accounts.first
      transaction = Transaction.create!(
        account: account,
        amount: Money.new(500, "USD"),
        date: Date.current,
        name: "STARBUCKS #123",
        kind: :standard
      )

      visit bulk_categorize_transactions_path

      # Select transaction
      check "transaction_ids_"

      # Apply categorization
      click_button "Apply Selected"

      assert_text "Categorization applied"

      # Verify transaction was categorized
      perform_enqueued_jobs
      transaction.reload
      assert_equal @category, transaction.category
    end

    test "transaction form shows suggestions for new transaction" do
      account = @family.accounts.first

      visit new_transaction_path

      # Fill in form with merchant name that matches pattern
      fill_in "Merchant", with: "STARBUCKS COFFEE"
      fill_in "Amount", with: "5.00"

      # Should show suggestion
      assert_text "Suggested categories"
      assert_text @category.name

      # Click suggestion
      within ".category-suggestions" do
        click_button @category.name
      end

      # Category should be selected
      assert_equal @category.id.to_s, find("#transaction_category_id").value
    end
  end
  ```

- [ ] Write integration test in `test/integration/pattern_learning_flow_test.rb`
  - Test complete flow: categorize → learn pattern → auto-categorize similar
  - Test pattern updates on repeat categorizations
  - Test pruning removes stale patterns

- [ ] Run full test suite: `bin/rails test`
- [ ] Run system tests: `bin/rails test:system`
- [ ] Run linting: `bin/rubocop -f github -a`
- [ ] Performance testing with larger datasets (1000+ transactions, 100+ patterns)

- [ ] Create user documentation
  - Overview of smart categorization feature
  - How pattern learning works
  - Using bulk categorization
  - Category suggestions in transaction form
  - Confidence levels explained
  - FAQ section

- [ ] Add inline help in UI
  - Tooltip explaining confidence scores
  - Help text for bulk categorization
  - "Why this suggestion?" tooltips in form

- [ ] Create admin/settings page for pattern management (optional)
  - View all patterns
  - Delete individual patterns
  - Disable/enable pattern matching per family
  - Re-train patterns manually

---

## Additional Considerations

### Performance Optimization
- Add database index on `transactions(merchant_id, category_id)` if not exists
- Consider PostgreSQL trigram indexes for fuzzy merchant matching at scale
- Cache pattern lookups in Redis for high-traffic families
- Batch process pattern learning to reduce database writes

### Future Enhancements (Not in Scope)
- Machine learning model (TF-IDF, neural network) for more sophisticated matching
- Category confidence boosting based on transaction amount patterns
- Temporal patterns (e.g., "coffee shops in the morning are usually personal, not business")
- Multi-merchant patterns (e.g., "transactions at grocery stores → groceries")
- User feedback loop ("Was this categorization correct?")
- A/B testing different confidence thresholds
- Pattern export/import for sharing across families
- Pattern versioning and rollback

### Edge Cases to Handle
- Transactions with no merchant and generic names (low confidence, skip)
- Multi-category merchants (e.g., Amazon for both shopping and subscriptions)
- Seasonal patterns (holiday spending, summer travel)
- One-time large purchases vs recurring small ones
- Merchant rebranding (old name → new name, should merge patterns)

### Privacy & Security
- Patterns scoped to families (multi-tenant isolation)
- No cross-family pattern sharing by default
- Pattern data included in family data exports
- GDPR compliance: patterns deleted when family deleted

---

**End of Implementation Plan**
