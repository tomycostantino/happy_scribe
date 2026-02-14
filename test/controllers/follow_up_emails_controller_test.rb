require "test_helper"

class FollowUpEmailsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    @meeting = meetings(:one)
    @email = follow_up_emails(:to_sarah)
  end

  test "show renders email preview" do
    get meeting_follow_up_email_url(@meeting, @email)
    assert_response :success
    assert_select "h1", text: @email.subject
    assert_select "p", text: /#{@meeting.title}/
  end

  test "show requires authentication" do
    sign_out
    get meeting_follow_up_email_url(@meeting, @email)
    assert_redirected_to new_session_url
  end

  test "show scopes to current user meetings" do
    sign_in_as(users(:two))
    get meeting_follow_up_email_url(@meeting, @email)
    assert_response :not_found
  end

  test "show renders email body" do
    get meeting_follow_up_email_url(@meeting, @email)
    assert_response :success
  end
end
