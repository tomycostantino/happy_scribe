class MeetingParticipantsController < ApplicationController
  include MeetingScoped

  before_action :set_meeting
  before_action :set_participant, only: %i[update destroy]

  def create
    @meeting.participants.create!(participant_params)
    render_participants
  rescue ActiveRecord::RecordInvalid => e
    redirect_to @meeting, alert: e.record.errors.full_messages.to_sentence
  end

  def update
    @participant.update!(participant_params)
    render_participants
  rescue ActiveRecord::RecordInvalid => e
    redirect_to @meeting, alert: e.record.errors.full_messages.to_sentence
  end

  def destroy
    @participant.destroy!
    render_participants
  end

  private

  def set_participant
    @participant = @meeting.participants.find(params[:id])
  end

  def participant_params
    params.require(:meeting_participant).permit(:contact_id, :role, :speaker_label)
  end

  def render_participants
    render partial: "meetings/participants", locals: { meeting: @meeting.reload }
  end
end
