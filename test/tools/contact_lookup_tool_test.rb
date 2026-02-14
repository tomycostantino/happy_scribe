require "test_helper"

class ContactLookupToolTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @tool = ContactLookupTool.new(@user)
  end

  test "returns contacts matching name with partial match" do
    result = @tool.execute(name: "Sarah")
    assert_includes result, "Sarah Chen"
    assert_includes result, "sarah@company.com"
    refute_includes result, "Tom Wilson"
  end

  test "returns all contacts when no name given" do
    result = @tool.execute
    assert_includes result, "Sarah Chen"
    assert_includes result, "Tom Wilson"
  end

  test "returns 'No contacts found.' when no matches" do
    result = @tool.execute(name: "Nonexistent Person")
    assert_equal "No contacts found.", result
  end

  test "formats output with name, email, and notes when present" do
    result = @tool.execute(name: "Sarah")
    assert_includes result, "Sarah Chen <sarah@company.com>"
    assert_includes result, "Engineering lead"
  end

  test "formats output without notes dash when notes are absent" do
    result = @tool.execute(name: "Tom")
    assert_includes result, "Tom Wilson <tom@company.com>"
    refute_includes result, " — ", "Should not have dash separator when notes are blank"
  end

  test "respects limit parameter" do
    result = @tool.execute(limit: 1)
    lines = result.strip.split("\n")
    assert_equal 1, lines.length
  end

  test "only returns current user's contacts" do
    other_user = users(:two)
    Contact.create!(user: other_user, name: "Secret Contact", email: "secret@other.com")

    result = @tool.execute
    refute_includes result, "Secret Contact"
    refute_includes result, "secret@other.com"
  end

  test "has correct tool description" do
    desc = ContactLookupTool.description
    assert_includes desc.downcase, "contacts"
    assert_includes desc.downcase, "address book"
  end

  test "orders results by name" do
    result = @tool.execute
    sarah_pos = result.index("Sarah Chen")
    tom_pos = result.index("Tom Wilson")
    assert sarah_pos < tom_pos, "Sarah should come before Tom alphabetically"
  end
end
