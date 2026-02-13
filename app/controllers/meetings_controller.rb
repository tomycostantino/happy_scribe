class MeetingsController < ApplicationController
  before_action :set_meeting, only: %i[show destroy]

  def index
    @meetings = Current.user.meetings.order(created_at: :desc)
  end

  def show
  end

  def new
    @meeting = Meeting.new(language: "en-US")
  end

  def create
    @meeting = Current.user.meetings.build(meeting_params)

    unless meeting_params[:recording].present?
      @meeting.errors.add(:recording, "must be attached")
      render :new, status: :unprocessable_entity
      return
    end

    if @meeting.save
      @meeting.create_transcript!(status: :pending)
      SubmitTranscriptionJob.perform_later(@meeting.id)
      redirect_to @meeting, notice: "Meeting uploaded. Transcription will begin shortly."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @meeting.destroy!
    redirect_to meetings_url, notice: "Meeting deleted."
  end

  private

  def set_meeting
    @meeting = Current.user.meetings.find(params[:id])
  end

  def meeting_params
    params.require(:meeting).permit(:title, :language, :recording)
  end
end
