require "test_helper"

class SendActionItemEmailToolTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper
  setup do
    @user = users(:one)
    @tool = SendActionItemEmailTool.new(@user)
    @meeting = meetings(:one)
  end

  # --- Draft tests ---

  test "draft returns preview with subject and body" do
    result = @tool.execute(
      action: "draft",
      recipient_email: "alice@example.com",
      meeting_id: @meeting.id
    )

    assert_includes result, "Subject:"
    assert_includes result, "Action items from Weekly Standup"
    assert_includes result, "Hi there"
  end

  test "draft includes action item descriptions in body" do
    result = @tool.execute(
      action: "draft",
      recipient_email: "alice@example.com",
      meeting_id: @meeting.id
    )

    assert_includes result, "Send the Q3 report to the finance team"
    assert_includes result, "Schedule follow-up meeting for next week"
  end

  test "draft filters by assignee when provided" do
    result = @tool.execute(
      action: "draft",
      recipient_email: "alice@example.com",
      meeting_id: @meeting.id,
      assignee: "Sarah"
    )

    assert_includes result, "Send the Q3 report to the finance team"
    refute_includes result, "Schedule follow-up meeting for next week"
  end

  test "draft returns error when no action items found" do
    result = @tool.execute(
      action: "draft",
      recipient_email: "alice@example.com",
      meeting_id: @meeting.id,
      assignee: "Nobody"
    )

    assert_includes result, "No action items found"
  end

  test "draft returns error when meeting not found" do
    result = @tool.execute(
      action: "draft",
      recipient_email: "alice@example.com",
      meeting_id: 999999
    )

    assert_includes result, "Meeting not found or access denied"
  end

  test "draft uses recipient_name in greeting when provided" do
    result = @tool.execute(
      action: "draft",
      recipient_email: "alice@example.com",
      recipient_name: "Alice",
      meeting_id: @meeting.id
    )

    assert_includes result, "Hi Alice"
  end

  test "draft uses 'there' in greeting when no name" do
    result = @tool.execute(
      action: "draft",
      recipient_email: "alice@example.com",
      meeting_id: @meeting.id
    )

    assert_includes result, "Hi there"
  end

  test "draft subject includes assignee name when filtered" do
    result = @tool.execute(
      action: "draft",
      recipient_email: "alice@example.com",
      meeting_id: @meeting.id,
      assignee: "Sarah"
    )

    assert_includes result, "Action items for Sarah from Weekly Standup"
  end

  test "draft includes due date when present" do
    result = @tool.execute(
      action: "draft",
      recipient_email: "alice@example.com",
      meeting_id: @meeting.id
    )

    assert_includes result, "due: 2026-02-19"
  end

  test "draft includes assignee annotation when present" do
    result = @tool.execute(
      action: "draft",
      recipient_email: "alice@example.com",
      meeting_id: @meeting.id
    )

    assert_includes result, "(assigned to: Sarah)"
  end

  # --- Send tests ---

  test "send creates FollowUpEmail record" do
    assert_difference "FollowUpEmail.count", 1 do
      @tool.execute(
        action: "send",
        recipient_email: "alice@example.com",
        meeting_id: @meeting.id
      )
    end

    email_record = FollowUpEmail.last
    assert_equal "alice@example.com", email_record.recipients
    assert_includes email_record.subject, "Action items from Weekly Standup"
    assert email_record.body.present?
    assert email_record.sent_at.present?
  end

  test "send enqueues email delivery" do
    assert_emails 1 do
      @tool.execute(
        action: "send",
        recipient_email: "alice@example.com",
        meeting_id: @meeting.id
      )
    end
  end

  test "send sets sent_at on the record" do
    freeze_time do
      @tool.execute(
        action: "send",
        recipient_email: "alice@example.com",
        meeting_id: @meeting.id
      )

      email_record = FollowUpEmail.last
      assert_equal Time.current, email_record.sent_at
    end
  end

  test "send returns confirmation message with count" do
    result = @tool.execute(
      action: "send",
      recipient_email: "alice@example.com",
      meeting_id: @meeting.id
    )

    assert_includes result, "Email sent to alice@example.com"
    assert_includes result, "2 action items"
    assert_includes result, "Weekly Standup"
  end

  test "send returns error when meeting not found" do
    result = @tool.execute(
      action: "send",
      recipient_email: "alice@example.com",
      meeting_id: 999999
    )

    assert_includes result, "Meeting not found or access denied"
  end

  # --- Invalid action tests ---

  test "invalid action returns error message" do
    result = @tool.execute(
      action: "invalid",
      recipient_email: "alice@example.com",
      meeting_id: @meeting.id
    )

    assert_includes result, "Invalid action"
  end

  # --- Assignee ILIKE matching ---

  test "draft filters by assignee case-insensitively" do
    result = @tool.execute(
      action: "draft",
      recipient_email: "alice@example.com",
      meeting_id: @meeting.id,
      assignee: "sarah"
    )

    assert_includes result, "Send the Q3 report to the finance team"
    refute_includes result, "Schedule follow-up meeting for next week"
  end
end
