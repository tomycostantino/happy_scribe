module CardsHelper
  def card(**options, &block)
    extra_class = options.delete(:class)
    css = "bg-white shadow-sm ring-1 ring-gray-900/5 rounded-lg"
    css = "#{css} #{extra_class}" if extra_class
    tag.div(class: css, **options, &block)
  end

  def auth_card(&block)
    tag.div(class: "bg-white shadow-sm ring-1 ring-gray-900/5 rounded-lg p-6", &block)
  end
end
