require "test_helper"

class ContactTest < ActiveSupport::TestCase
  test "valid contact with name, email, and user" do
    contact = Contact.new(
      name: "Jane Doe",
      email: "jane@example.com",
      user: users(:one)
    )
    assert contact.valid?
  end

  test "requires name" do
    contact = Contact.new(email: "jane@example.com", user: users(:one))
    assert_not contact.valid?
    assert_includes contact.errors[:name], "can't be blank"
  end

  test "requires email" do
    contact = Contact.new(name: "Jane Doe", user: users(:one))
    assert_not contact.valid?
    assert_includes contact.errors[:email], "can't be blank"
  end

  test "requires user" do
    contact = Contact.new(name: "Jane Doe", email: "jane@example.com")
    assert_not contact.valid?
    assert_includes contact.errors[:user], "must exist"
  end

  test "validates email format" do
    contact = Contact.new(name: "Jane Doe", email: "not-an-email", user: users(:one))
    assert_not contact.valid?
    assert_includes contact.errors[:email], "is invalid"
  end

  test "normalizes email by stripping whitespace and lowercasing" do
    contact = Contact.new(
      name: "Jane Doe",
      email: "  JANE@EXAMPLE.COM  ",
      user: users(:one)
    )
    assert_equal "jane@example.com", contact.email
  end

  test "enforces unique email per user" do
    Contact.create!(name: "First", email: "dupe@example.com", user: users(:one))
    duplicate = Contact.new(name: "Second", email: "dupe@example.com", user: users(:one))
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:email], "has already been taken"
  end

  test "allows same email for different users" do
    Contact.create!(name: "First", email: "shared@example.com", user: users(:one))
    other_user_contact = Contact.new(name: "Second", email: "shared@example.com", user: users(:two))
    assert other_user_contact.valid?
  end

  test "search_by_name matches partial name case-insensitively" do
    # Fixtures: sarah (Sarah Chen), tom (Tom Wilson)
    results = Contact.search_by_name("sarah")
    assert_includes results, contacts(:sarah)
    assert_not_includes results, contacts(:tom)

    results = Contact.search_by_name("CHEN")
    assert_includes results, contacts(:sarah)

    results = Contact.search_by_name("wil")
    assert_includes results, contacts(:tom)
    assert_not_includes results, contacts(:sarah)
  end

  test "notes are optional" do
    contact = Contact.new(
      name: "Jane Doe",
      email: "jane@example.com",
      user: users(:one),
      notes: nil
    )
    assert contact.valid?
  end
end
