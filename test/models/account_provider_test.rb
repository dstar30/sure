require "test_helper"

class AccountProviderTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:depository)
    @family = families(:dylan_family)

    # Create provider items
    @plaid_item = PlaidItem.create!(
      family: @family,
      plaid_id: "test_plaid_item",
      access_token: "test_token",
      name: "Test Bank"
    )

    # Create provider accounts
    @plaid_account = PlaidAccount.create!(
      plaid_item: @plaid_item,
      name: "Plaid Checking",
      plaid_id: "plaid_123",
      plaid_type: "depository",
      currency: "USD",
      current_balance: 1000
    )
  end

  test "prevents duplicate provider type for same account" do
    # Create first PlaidAccount link
    AccountProvider.create!(
      account: @account,
      provider: @plaid_account
    )

    # Create another PlaidAccount
    another_plaid_account = PlaidAccount.create!(
      plaid_item: @plaid_item,
      name: "Another Plaid Account",
      plaid_id: "plaid_456",
      plaid_type: "savings",
      currency: "USD",
      current_balance: 5000
    )

    # Should not be able to link another PlaidAccount to same account
    duplicate_provider = AccountProvider.new(
      account: @account,
      provider: another_plaid_account
    )

    assert_not duplicate_provider.valid?
    assert_includes duplicate_provider.errors[:account_id], "has already been taken"
  end

  test "prevents same provider account from linking to multiple accounts" do
    # Link provider to first account
    AccountProvider.create!(
      account: @account,
      provider: @plaid_account
    )

    # Try to link same provider to another account
    another_account = accounts(:investment)

    duplicate_link = AccountProvider.new(
      account: another_account,
      provider: @plaid_account
    )

    assert_not duplicate_link.valid?
    assert_includes duplicate_link.errors[:provider_id], "has already been taken"
  end

  test "adapter method returns correct adapter" do
    provider = AccountProvider.create!(
      account: @account,
      provider: @plaid_account
    )

    adapter = provider.adapter

    assert_kind_of Provider::PlaidAdapter, adapter
    assert_equal "plaid", adapter.provider_name
    assert_equal @account, adapter.account
  end
end
