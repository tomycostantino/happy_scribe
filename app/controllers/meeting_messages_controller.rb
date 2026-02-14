class MeetingMessagesController < ApplicationController
  include MeetingScoped

  before_action :set_meeting
  before_action :set_chat

  def create
    return head :bad_request unless content.present?

    @message = @chat.send_message(content)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to meeting_chat_path(@meeting, @chat) }
    end
  end

  private

  def content
    params.dig(:message, :content)
  end
end
