module NavigationHelper
  def back_link(text, url, **options)
    link_to url, class: "inline-flex items-center gap-1 text-sm font-medium text-indigo-600 hover:text-indigo-500", **options do
      back_arrow_icon + text
    end
  end

  def page_header(title, &block)
    tag.div(class: "flex justify-between items-center mb-8") do
      tag.h1(title, class: "text-2xl font-bold text-gray-900") +
        (block_given? ? tag.div(class: "flex items-center gap-3", &block) : "".html_safe)
    end
  end

  def auth_page_title(title)
    tag.h1(title, class: "text-2xl font-bold text-center text-gray-900 mb-8")
  end

  def auth_footer_link(text, url)
    tag.p(class: "mt-6 text-center text-sm text-gray-500") do
      link_to text, url, class: "font-medium text-indigo-600 hover:text-indigo-500"
    end
  end
end
