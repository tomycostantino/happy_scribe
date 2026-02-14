class MessagesController < ApplicationController
  before_action :set_chat

  def create
    return head :bad_request unless content.present?

    ChatResponseJob.perform_later(@chat.id, content)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @chat }
    end
  end

  private

  def set_chat
    @chat = Current.user.chats.find(params[:chat_id])
  end

  def content
    params.dig(:message, :content)
  end
end
