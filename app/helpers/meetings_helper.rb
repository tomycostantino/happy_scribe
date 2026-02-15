module MeetingsHelper
  def status_badge(meeting)
    colors = {
      "uploading" => "bg-blue-100 text-blue-800",
      "transcribing" => "bg-yellow-100 text-yellow-800",
      "transcribed" => "bg-green-100 text-green-800",
      "processing" => "bg-purple-100 text-purple-800",
      "completed" => "bg-green-100 text-green-800",
      "failed" => "bg-red-100 text-red-800"
    }
    tag.span(
      meeting.status.humanize,
      id: "meeting_#{meeting.id}_status",
      class: "inline-block px-2 py-1 text-xs font-medium rounded-full #{colors[meeting.status]}"
    )
  end

  def section_header(title)
    tag.h2(title, class: "text-sm font-semibold text-gray-900 uppercase tracking-wide")
  end
end
