module EmptyStatesHelper
  # Renders an empty state with icon, title, optional subtitle, and optional block for action buttons
  #
  # Example:
  #   <%= empty_state(icon: :microphone, title: "No meetings yet", subtitle: "Upload your first recording.") do %>
  #     <%= primary_button "New Meeting", new_meeting_path %>
  #   <% end %>
  #
  def empty_state(icon: nil, title:, subtitle: nil, **options, &block)
    tag.div(class: "py-12 text-center") do
      parts = []
      if icon
        icon_method = "#{icon}_icon"
        parts << send(icon_method, css_class: "mx-auto h-10 w-10 text-gray-400 mb-3") if respond_to?(icon_method, true)
      end
      parts << tag.p(title, class: "text-sm font-medium text-gray-900")
      parts << tag.p(subtitle, class: "text-sm text-gray-500 mt-1") if subtitle
      parts << capture(&block) if block_given?
      safe_join(parts)
    end
  end
end
