module TransactionsHelper
  def transaction_search_filters
    [
      { key: "account_filter", label: "Account", icon: "layers" },
      { key: "date_filter", label: "Date", icon: "calendar" },
      { key: "type_filter", label: "Type", icon: "tag" },
      { key: "amount_filter", label: "Amount", icon: "hash" },
      { key: "category_filter", label: "Category", icon: "shapes" },
      { key: "tag_filter", label: "Tag", icon: "tags" },
      { key: "merchant_filter", label: "Merchant", icon: "store" }
    ]
  end

  def get_transaction_search_filter_partial_path(filter)
    "transactions/searches/filters/#{filter[:key]}"
  end

  def get_default_transaction_search_filter
    transaction_search_filters[0]
  end

  # ---- Transaction extra details helpers ----
  # Returns a structured hash describing extra details for a transaction.
  # Input can be a Transaction or an Entry (responds_to :transaction).
  # Structure:
  #   {
  #     kind: :simplefin | :raw,
  #     simplefin: { payee:, description:, memo: },
  #     provider_extras: [ { key:, value:, title: } ],
  #     raw: String (pretty JSON or string)
  #   }
  def build_transaction_extra_details(obj)
    tx = obj.respond_to?(:transaction) ? obj.transaction : obj
    return nil unless tx.respond_to?(:extra) && tx.extra.present?

    extra = tx.extra

    pretty = begin
      JSON.pretty_generate(extra)
    rescue StandardError
      extra.to_s
    end
    {
      kind: :raw,
      simplefin: {},
      provider_extras: [],
      raw: pretty
    }
  end
end
