class MeetingChatsController < ApplicationController
  include MeetingScoped

  before_action :set_meeting
  before_action :set_chat, only: [ :show ]

  # GET /meetings/:meeting_id/chats — lazy-loaded turbo frame content
  def index
    @chats = @meeting.chats.where(user: Current.user).order(created_at: :desc)
  end

  # POST /meetings/:meeting_id/chats — start a new chat
  def create
    @chat = @meeting.chats.create!(user: Current.user)
    @chat.send_message(params[:prompt]) if params[:prompt].present?

    redirect_to meeting_chat_path(@meeting, @chat)
  end

  # GET /meetings/:meeting_id/chats/:id — show a specific chat
  def show
    @message = @chat.messages.build
  end
end
