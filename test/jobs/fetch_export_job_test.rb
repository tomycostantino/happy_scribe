require "test_helper"

class FetchExportJobTest < ActiveJob::TestCase
  test "delegates to HappyScribe::ExportFetch" do
    called_with = nil

    HappyScribe::ExportFetch.stub(:perform_now, ->(id, poll_count:) { called_with = { id: id, poll_count: poll_count } }) do
      FetchExportJob.perform_now(42, poll_count: 3)
    end

    assert_equal({ id: 42, poll_count: 3 }, called_with)
  end
end
