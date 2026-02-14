require "test_helper"

class MeetingTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "valid meeting with required attributes" do
    meeting = Meeting.new(
      title: "Weekly Standup",
      language: "en-US",
      user: users(:one)
    )
    meeting.recording.attach(
      io: File.open(Rails.root.join("test/fixtures/files/sample.mp3")),
      filename: "sample.mp3",
      content_type: "audio/mpeg"
    )
    assert meeting.valid?
  end

  test "requires a title" do
    meeting = Meeting.new(language: "en-US", user: users(:one))
    assert_not meeting.valid?
    assert_includes meeting.errors[:title], "can't be blank"
  end

  test "requires a user" do
    meeting = Meeting.new(title: "Test", language: "en-US")
    assert_not meeting.valid?
    assert_includes meeting.errors[:user], "must exist"
  end

  test "requires a recording" do
    meeting = Meeting.new(title: "Test", language: "en-US", user: users(:one))
    assert_not meeting.valid?
    assert_includes meeting.errors[:recording], "must be attached"
  end

  test "defaults status to uploading" do
    meeting = Meeting.new
    assert_equal "uploading", meeting.status
  end

  test "defaults language to en-US" do
    meeting = Meeting.new
    assert_equal "en-US", meeting.language
  end

  test "defaults source to uploaded" do
    meeting = Meeting.new
    assert_equal "uploaded", meeting.source
  end

  test "source enum values" do
    assert_equal(
      { "uploaded" => "uploaded", "imported" => "imported" },
      Meeting.sources
    )
  end

  test "imported meeting does not require recording" do
    meeting = Meeting.new(
      title: "Imported Meeting",
      language: "en-US",
      user: users(:one),
      source: :imported
    )
    assert meeting.valid?
  end

  test "imported meeting does not auto-start transcription" do
    meeting = Meeting.new(
      title: "Imported Meeting",
      language: "en-US",
      user: users(:one),
      source: :imported,
      status: :transcribing
    )

    assert_no_enqueued_jobs(only: HappyScribe::Transcription::SubmitJob) do
      meeting.save!
    end

    assert_nil meeting.transcript
  end

  test "status enum values" do
    assert_equal(
      { "uploading" => "uploading", "transcribing" => "transcribing",
        "transcribed" => "transcribed", "processing" => "processing",
        "completed" => "completed", "failed" => "failed" },
      Meeting.statuses
    )
  end

  test "belongs to user" do
    meeting = meetings(:one)
    assert_instance_of User, meeting.user
  end

  test "creates transcript and enqueues job after create" do
    meeting = Meeting.new(
      title: "Weekly Standup",
      language: "en-US",
      user: users(:one)
    )
    meeting.recording.attach(
      io: File.open(Rails.root.join("test/fixtures/files/sample.mp3")),
      filename: "sample.mp3",
      content_type: "audio/mpeg"
    )

    assert_enqueued_with(job: HappyScribe::Transcription::SubmitJob) do
      meeting.save!
    end

    assert meeting.transcript.present?
    assert_equal "pending", meeting.transcript.status
  end
end
