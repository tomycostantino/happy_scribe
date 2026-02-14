require "test_helper"

class ManageContactToolTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @tool = ManageContactTool.new(@user)
  end

  test "creates a new contact with name and email" do
    result = @tool.execute(name: "Jane Doe", email: "jane@example.com")

    assert_equal 'Saved contact: Jane Doe <jane@example.com>', result
    assert @user.contacts.exists?(email: "jane@example.com", name: "Jane Doe")
  end

  test "creates a contact with optional notes" do
    result = @tool.execute(name: "Jane Doe", email: "jane@example.com", notes: "Product manager")

    contact = @user.contacts.find_by(email: "jane@example.com")
    assert contact.present?
    assert_equal "Product manager", contact.notes
    assert_includes result, "Saved contact"
  end

  test "updates existing contact when same email exists" do
    existing = contacts(:sarah)
    original_email = existing.email

    result = @tool.execute(name: "Sarah Chen-Smith", email: original_email, notes: "VP Engineering")

    existing.reload
    assert_equal "Sarah Chen-Smith", existing.name
    assert_equal "VP Engineering", existing.notes
    assert_includes result, "Updated contact"
    assert_includes result, "Sarah Chen-Smith"
    assert_includes result, original_email
  end

  test "returns 'Saved contact' for new contacts" do
    result = @tool.execute(name: "New Person", email: "new@example.com")

    assert_match(/\ASaved contact: New Person <new@example\.com>\z/, result)
  end

  test "returns 'Updated contact' for existing contacts" do
    result = @tool.execute(name: "Tom W.", email: "tom@company.com")

    assert_match(/\AUpdated contact: Tom W\. <tom@company\.com>\z/, result)
  end

  test "handles invalid email gracefully" do
    result = @tool.execute(name: "Bad Email", email: "not-an-email")

    assert_includes result, "Failed"
    refute @user.contacts.exists?(name: "Bad Email")
  end

  test "handles missing name gracefully" do
    result = @tool.execute(name: "", email: "valid@example.com")

    assert_includes result, "Failed"
    refute @user.contacts.exists?(email: "valid@example.com")
  end

  test "normalizes email by stripping whitespace and lowercasing" do
    result = @tool.execute(name: "Mixed Case", email: "  MiXeD@Example.COM  ")

    contact = @user.contacts.find_by(email: "mixed@example.com")
    assert contact.present?, "Expected contact with normalized email"
    assert_includes result, "mixed@example.com"
  end

  test "has correct tool description" do
    assert_includes ManageContactTool.description.downcase, "contact"
  end
end
