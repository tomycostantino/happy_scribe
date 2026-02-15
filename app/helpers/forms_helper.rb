module FormsHelper
  def form_errors(record)
    return unless record.errors.any?

    tag.div(class: "rounded-md bg-red-50 p-3") do
      tag.div(class: "text-sm text-red-700") do
        safe_join(record.errors.full_messages.map { |msg| tag.p(msg) })
      end
    end
  end

  def form_input_class(variant: :default)
    case variant
    when :default
      "block w-full rounded-md border-0 py-2 px-3 text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 placeholder:text-gray-400 focus:ring-2 focus:ring-inset focus:ring-indigo-600 text-sm"
    when :compact
      "mt-1 w-full rounded-md border-0 py-1.5 px-3 text-sm text-gray-900 ring-1 ring-inset ring-gray-300 placeholder:text-gray-400 focus:ring-2 focus:ring-inset focus:ring-indigo-600"
    when :chat
      "flex-1 rounded-md border border-gray-300 px-3 py-2 text-sm shadow-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500 resize-none"
    end
  end

  def form_label_class
    "block text-sm font-medium text-gray-700"
  end

  def form_select_class
    "block w-full rounded-md border-0 py-2 px-3 text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 focus:ring-2 focus:ring-inset focus:ring-indigo-600 text-sm bg-white"
  end
end
