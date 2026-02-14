module MeetingScoped
  extend ActiveSupport::Concern

  private

  def set_meeting
    @meeting = Current.user.meetings.find(params[:meeting_id])
  end

  def set_chat
    @chat = @meeting.chats.where(user: Current.user).find(params[:chat_id] || params[:id])
  end
end
