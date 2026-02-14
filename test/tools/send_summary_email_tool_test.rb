require "test_helper"

class SendSummaryEmailToolTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @user = users(:one)
    @tool = SendSummaryEmailTool.new(@user)
    @meeting = meetings(:one)

    # Ensure clean state — destroy any existing summary first
    @meeting.summary&.destroy
    summary = @meeting.create_summary!(model_used: "test")
    summary.update!(content: "Key decisions were made about the Q3 roadmap. The team agreed to prioritize the API refactor.")
  end

  # --- Send tests ---

  test "creates FollowUpEmail record and sends immediately" do
    assert_difference "FollowUpEmail.count", 1 do
      @tool.execute(
        recipient_email: "alice@example.com",
        meeting_id: @meeting.id
      )
    end

    email_record = FollowUpEmail.last
    assert_equal "alice@example.com", email_record.recipients
    assert_includes email_record.subject, "Summary: Weekly Standup"
    assert email_record.body.present?
    assert email_record.sent_at.present?
  end

  test "enqueues email delivery" do
    assert_emails 1 do
      @tool.execute(
        recipient_email: "alice@example.com",
        meeting_id: @meeting.id
      )
    end
  end

  test "sets sent_at on the record" do
    freeze_time do
      @tool.execute(
        recipient_email: "alice@example.com",
        meeting_id: @meeting.id
      )

      email_record = FollowUpEmail.last
      assert_equal Time.current, email_record.sent_at
    end
  end

  test "returns confirmation message" do
    result = @tool.execute(
      recipient_email: "alice@example.com",
      meeting_id: @meeting.id
    )

    assert_includes result, "Email sent to alice@example.com"
    assert_includes result, "Weekly Standup"
  end

  test "includes summary content in body" do
    @tool.execute(
      recipient_email: "alice@example.com",
      meeting_id: @meeting.id
    )

    email_record = FollowUpEmail.last
    assert_includes email_record.body.to_plain_text, "Q3 roadmap"
    assert_includes email_record.body.to_plain_text, "API refactor"
  end

  # --- Greeting tests ---

  test "uses recipient_name in greeting when provided" do
    @tool.execute(
      recipient_email: "alice@example.com",
      recipient_name: "Alice",
      meeting_id: @meeting.id
    )

    email_record = FollowUpEmail.last
    assert_includes email_record.body.to_plain_text, "Hi Alice"
  end

  test "uses 'there' in greeting when no name" do
    @tool.execute(
      recipient_email: "alice@example.com",
      meeting_id: @meeting.id
    )

    email_record = FollowUpEmail.last
    assert_includes email_record.body.to_plain_text, "Hi there"
  end

  # --- Error handling ---

  test "returns error when no summary available" do
    @meeting.summary.destroy

    result = @tool.execute(
      recipient_email: "alice@example.com",
      meeting_id: @meeting.id
    )

    assert_includes result, "No summary available"
  end

  test "returns error when meeting not found" do
    result = @tool.execute(
      recipient_email: "alice@example.com",
      meeting_id: 999999
    )

    assert_includes result, "Meeting not found or access denied"
  end

  test "cannot access another user's meeting" do
    other_user = users(:two)
    Meeting.insert({
      title: "Other", language: "en-US", status: "completed",
      user_id: other_user.id, created_at: Time.current, updated_at: Time.current
    })
    other_id = Meeting.where(user: other_user).last.id

    result = @tool.execute(
      recipient_email: "alice@example.com",
      meeting_id: other_id
    )

    assert_includes result, "Meeting not found or access denied"
  end
end
