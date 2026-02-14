require "test_helper"

class ContactsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    @contact = contacts(:sarah)
  end

  test "index lists contacts" do
    get contacts_url
    assert_response :success
    assert_select "p", text: "Sarah Chen"
  end

  test "index requires authentication" do
    sign_out
    get contacts_url
    assert_redirected_to new_session_url
  end

  test "index filters by search query" do
    get contacts_url, params: { query: "sarah" }
    assert_response :success
    assert_select "p", text: "Sarah Chen"
    assert_select "p", text: "Tom Wilson", count: 0
  end

  test "index shows empty state when no results" do
    get contacts_url, params: { query: "nonexistent" }
    assert_response :success
    assert_select "p", text: /No contacts matching/
  end

  test "show displays contact" do
    get contact_url(@contact)
    assert_response :success
  end

  test "show scopes to current user" do
    sign_in_as(users(:two))
    get contact_url(@contact)
    assert_response :not_found
  end

  test "new shows form" do
    get new_contact_url
    assert_response :success
  end

  test "create with valid params" do
    assert_difference("Contact.count") do
      post contacts_url, params: {
        contact: { name: "Alice", email: "alice@example.com", notes: "New hire" }
      }
    end
    assert_redirected_to contacts_url
  end

  test "create without name fails" do
    assert_no_difference("Contact.count") do
      post contacts_url, params: {
        contact: { name: "", email: "alice@example.com" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "create with duplicate email fails" do
    assert_no_difference("Contact.count") do
      post contacts_url, params: {
        contact: { name: "Sarah Duplicate", email: @contact.email }
      }
    end
    assert_response :unprocessable_entity
  end

  test "edit shows form" do
    get edit_contact_url(@contact)
    assert_response :success
  end

  test "update with valid params" do
    patch contact_url(@contact), params: {
      contact: { name: "Sarah Updated" }
    }
    assert_redirected_to contacts_url
    assert_equal "Sarah Updated", @contact.reload.name
  end

  test "update with invalid params fails" do
    patch contact_url(@contact), params: {
      contact: { email: "" }
    }
    assert_response :unprocessable_entity
  end

  test "destroy removes contact" do
    assert_difference("Contact.count", -1) do
      delete contact_url(@contact)
    end
    assert_redirected_to contacts_url
  end

  test "destroy scopes to current user" do
    sign_in_as(users(:two))
    assert_no_difference("Contact.count") do
      delete contact_url(@contact)
    end
    assert_response :not_found
  end
end
