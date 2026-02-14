require "test_helper"

class FollowUpEmailTest < ActiveSupport::TestCase
  setup do
    @meeting = meetings(:one)
    @follow_up = follow_up_emails(:one)
    @follow_up.update!(body: "<p>Here are the action items from our meeting.</p>")
  end

  test "valid follow-up email with required fields" do
    email = FollowUpEmail.new(
      meeting: @meeting,
      recipients: "alice@example.com",
      subject: "Follow-up: Weekly Standup"
    )
    email.body = "<p>Action items discussed.</p>"
    assert email.valid?
  end

  test "requires recipients" do
    email = FollowUpEmail.new(
      meeting: @meeting,
      subject: "Follow-up",
      body: "<p>Content</p>"
    )
    assert_not email.valid?
    assert_includes email.errors[:recipients], "can't be blank"
  end

  test "requires subject" do
    email = FollowUpEmail.new(
      meeting: @meeting,
      recipients: "alice@example.com",
      body: "<p>Content</p>"
    )
    assert_not email.valid?
    assert_includes email.errors[:subject], "can't be blank"
  end

  test "requires body" do
    email = FollowUpEmail.new(
      meeting: @meeting,
      recipients: "alice@example.com",
      subject: "Follow-up"
    )
    assert_not email.valid?
    assert_includes email.errors[:body], "can't be blank"
  end

  test "belongs to meeting" do
    assert_instance_of Meeting, @follow_up.meeting
    assert_equal @meeting, @follow_up.meeting
  end

  test "recipient_list splits comma-separated emails and strips whitespace" do
    @follow_up.update!(recipients: "alice@example.com, bob@example.com , charlie@example.com")
    assert_equal [ "alice@example.com", "bob@example.com", "charlie@example.com" ], @follow_up.recipient_list
  end

  test "recipient_list handles single email" do
    @follow_up.update!(recipients: "alice@example.com")
    assert_equal [ "alice@example.com" ], @follow_up.recipient_list
  end

  test "sent? returns true when sent_at present" do
    @follow_up.update!(sent_at: Time.current)
    assert @follow_up.sent?
  end

  test "sent? returns false when sent_at nil" do
    @follow_up.update!(sent_at: nil)
    assert_not @follow_up.sent?
  end

  test "sent scope returns only sent emails" do
    sent_email = @follow_up
    assert sent_email.sent_at.present?, "fixture :one should have sent_at set"

    draft_email = FollowUpEmail.create!(
      meeting: @meeting,
      recipients: "draft@example.com",
      subject: "Draft Email",
      body: "<p>Draft content</p>",
      sent_at: nil
    )

    sent_results = FollowUpEmail.sent
    assert_includes sent_results, sent_email
    assert_not_includes sent_results, draft_email
  end

  test "sent_at is optional for draft state" do
    email = FollowUpEmail.new(
      meeting: @meeting,
      recipients: "alice@example.com",
      subject: "Draft Follow-up"
    )
    email.body = "<p>Draft content</p>"
    email.sent_at = nil
    assert email.valid?
  end
end
