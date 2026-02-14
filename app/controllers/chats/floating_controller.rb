class Chats::FloatingController < ApplicationController
  def show
    @chat = Current.user.chats.where(meeting_id: nil).order(created_at: :desc).first
    @chat ||= Current.user.chats.create!
    @message = @chat.messages.build
  end

  def create
    @chat = Current.user.chats.create!
    @message = @chat.messages.build

    render :show
  end
end
