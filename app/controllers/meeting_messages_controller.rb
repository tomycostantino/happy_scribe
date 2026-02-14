class MeetingMessagesController < ApplicationController
  before_action :set_meeting
  before_action :set_chat

  def create
    return unless content.present?

    ChatResponseJob.perform_later(@chat.id, content)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to meeting_chat_path(@meeting, @chat) }
    end
  end

  private

  def set_meeting
    @meeting = Current.user.meetings.find(params[:meeting_id])
  end

  def set_chat
    @chat = @meeting.chats.where(user: Current.user).find(params[:chat_id])
  end

  def content
    params[:message][:content]
  end
end
