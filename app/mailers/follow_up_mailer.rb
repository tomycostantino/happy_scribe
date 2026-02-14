class FollowUpMailer < ApplicationMailer
  def action_items(follow_up_email)
    @follow_up_email = follow_up_email
    @meeting = follow_up_email.meeting

    mail(
      to: follow_up_email.recipient_list,
      subject: follow_up_email.subject
    )
  end

  def summary(follow_up_email)
    @follow_up_email = follow_up_email
    @meeting = follow_up_email.meeting

    mail(
      to: follow_up_email.recipient_list,
      subject: follow_up_email.subject
    )
  end
end
