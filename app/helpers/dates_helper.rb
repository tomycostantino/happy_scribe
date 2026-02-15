module DatesHelper
  # "Feb 15, 2026 at 14:30" — used in meetings list, headers, imports
  def formatted_datetime(time)
    time.strftime("%b %d, %Y at %H:%M")
  end

  # "Feb 15, 2026" — used in contacts/show
  def formatted_date(date)
    date.strftime("%b %-d, %Y")
  end

  # "Feb 15, 2026 at 2:30 PM" — used in follow_up_emails
  def formatted_datetime_long(time)
    time.strftime("%b %-d, %Y at %-I:%M %p")
  end

  # "Feb 15 at 14:30" — used in meeting_chats
  def short_datetime(time)
    time.strftime("%b %d at %H:%M")
  end

  # "Feb 15" — used in action_items due dates
  def short_date(date)
    date.strftime("%b %d")
  end
end
