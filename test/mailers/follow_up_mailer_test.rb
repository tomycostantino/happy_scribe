require "test_helper"

class FollowUpMailerTest < ActionMailer::TestCase
  setup do
    @follow_up_email = follow_up_emails(:one)
    @follow_up_email.update!(body: "Hi everyone,\n\nHere are your action items from the meeting:\n\n- Review the budget\n- Send the report")
  end

  test "action_items sends to all recipients from recipient_list" do
    email = FollowUpMailer.action_items(@follow_up_email)

    assert_equal [ "alice@example.com", "bob@example.com" ], email.to
  end

  test "action_items sets correct subject" do
    email = FollowUpMailer.action_items(@follow_up_email)

    assert_equal "Follow-up: Weekly Standup", email.subject
  end

  test "action_items includes body content in html part" do
    email = FollowUpMailer.action_items(@follow_up_email)

    assert_match "Review the budget", email.html_part.body.to_s
    assert_match "Send the report", email.html_part.body.to_s
  end

  test "action_items includes body content in text part" do
    email = FollowUpMailer.action_items(@follow_up_email)

    assert_match "Review the budget", email.text_part.body.to_s
    assert_match "Send the report", email.text_part.body.to_s
  end

  test "action_items includes meeting title in email" do
    email = FollowUpMailer.action_items(@follow_up_email)

    assert_match "Weekly Standup", email.html_part.body.to_s
  end
end
