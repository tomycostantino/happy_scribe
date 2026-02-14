class FollowUpEmailsController < ApplicationController
  def show
    @meeting = Current.user.meetings.find(params[:meeting_id])
    @email = @meeting.follow_up_emails.find(params[:id])
  end
end
