class MeetingParticipantsController < ApplicationController
  include MeetingScoped

  before_action :set_meeting
  before_action :set_participant, only: %i[update destroy]

  def create
    @participant = @meeting.participants.build(participant_params)
    if @participant.save
      redirect_to @meeting, notice: "Participant added."
    else
      redirect_to @meeting, alert: @participant.errors.full_messages.to_sentence
    end
  end

  def update
    if @participant.update(participant_params)
      redirect_to @meeting, notice: "Participant updated."
    else
      redirect_to @meeting, alert: @participant.errors.full_messages.to_sentence
    end
  end

  def destroy
    @participant.destroy!
    redirect_to @meeting, notice: "Participant removed."
  end

  private

  def set_participant
    @participant = @meeting.participants.find(params[:id])
  end

  def participant_params
    params.require(:participant).permit(:contact_id, :role, :speaker_label)
  end
end
