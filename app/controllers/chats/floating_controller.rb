class Chats::FloatingController < ApplicationController
  before_action :set_chat, only: %i[show destroy]

  def index
    @chats = Current.user.chats.where(meeting_id: nil).order(created_at: :desc)
  end

  def show
    @message = @chat.messages.build
  end

  def create
    @chat = Current.user.chats.create!
    @message = @chat.messages.build

    render :show
  end

  def destroy
    @chat.destroy
    @chats = Current.user.chats.where(meeting_id: nil).order(created_at: :desc)

    render :index
  end

  private

  def set_chat
    @chat = Current.user.chats.find(params[:id])
  end
end
