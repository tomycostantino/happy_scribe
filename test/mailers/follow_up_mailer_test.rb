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

  # --- Summary email tests ---

  test "summary sends to recipient" do
    summary_email = follow_up_emails(:summary_email)
    summary_email.update!(body: "Hi there,\n\nHere is the summary from the meeting.\n\nKey decisions about Q3 roadmap.")

    email = FollowUpMailer.summary(summary_email)

    assert_equal [ "alice@example.com" ], email.to
  end

  test "summary sets correct subject" do
    summary_email = follow_up_emails(:summary_email)
    summary_email.update!(body: "Meeting summary content")

    email = FollowUpMailer.summary(summary_email)

    assert_equal "Summary: Weekly Standup", email.subject
  end

  test "summary includes body content in html part" do
    summary_email = follow_up_emails(:summary_email)
    summary_email.update!(body: "Key decisions about Q3 roadmap and API refactor.")

    email = FollowUpMailer.summary(summary_email)

    assert_match "Q3 roadmap", email.html_part.body.to_s
    assert_match "API refactor", email.html_part.body.to_s
  end

  test "summary includes body content in text part" do
    summary_email = follow_up_emails(:summary_email)
    summary_email.update!(body: "Key decisions about Q3 roadmap and API refactor.")

    email = FollowUpMailer.summary(summary_email)

    assert_match "Q3 roadmap", email.text_part.body.to_s
    assert_match "API refactor", email.text_part.body.to_s
  end

  test "summary includes meeting title in email" do
    summary_email = follow_up_emails(:summary_email)
    summary_email.update!(body: "Summary content")

    email = FollowUpMailer.summary(summary_email)

    assert_match "Weekly Standup", email.html_part.body.to_s
  end
end
