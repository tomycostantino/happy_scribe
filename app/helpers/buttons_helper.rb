module ButtonsHelper
  def primary_button(text_or_url = nil, url = nil, size: :md, inline: false, **options, &block)
    css = primary_button_class(size: size, inline: inline)
    if block_given?
      link_to(text_or_url, class: css, **options, &block)
    else
      link_to(text_or_url, url, class: css, **options)
    end
  end

  def primary_button_class(size: :md, inline: false)
    size_classes = { sm: "py-1.5 px-3", md: "py-2 px-4", full: "w-full py-2 px-4" }
    classes = []
    classes << "inline-flex items-center gap-2" if inline
    classes << "rounded-md bg-indigo-600 #{size_classes[size]} text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600 cursor-pointer"
    classes.join(" ")
  end

  def secondary_button(text_or_url = nil, url = nil, **options, &block)
    css = secondary_button_class
    if block_given?
      link_to(text_or_url, class: css, **options, &block)
    else
      link_to(text_or_url, url, class: css, **options)
    end
  end

  def secondary_button_class
    "inline-flex items-center gap-2 rounded-md bg-white py-2 px-4 text-sm font-semibold text-gray-700 shadow-sm ring-1 ring-gray-300 hover:bg-gray-50"
  end

  def delete_button(url, confirm: "Are you sure?", **options, &block)
    turbo_data = { turbo_confirm: confirm }
    turbo_data.merge!(options.delete(:data) || {})

    button_to url, method: :delete,
      class: "text-gray-400 hover:text-red-500 transition-colors cursor-pointer",
      data: turbo_data,
      **options do
      block_given? ? capture(&block) : trash_icon
    end
  end

  def edit_button(url, **options, &block)
    data = options.delete(:data) || {}
    link_to url, class: "text-gray-400 hover:text-indigo-500 transition-colors", data: data, **options do
      block_given? ? capture(&block) : pencil_icon
    end
  end

  def cancel_link(url, text: "Cancel", **options)
    link_to text, url, class: "text-sm font-medium text-gray-600 hover:text-gray-500", **options
  end
end
