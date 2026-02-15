class FollowUpEmailsController < ApplicationController
  include MeetingScoped

  before_action :set_meeting, only: :show

  def show
    @email = @meeting.follow_up_emails.find(params[:id])
  end
end
