module IconsHelper
  def trash_icon(css_class: "h-4 w-4", **options)
    heroicon(
      "m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0",
      css_class: css_class,
      stroke_width: "1.5",
      **options
    )
  end

  def pencil_icon(css_class: "h-4 w-4", **options)
    heroicon(
      "m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L6.832 19.82a4.5 4.5 0 0 1-1.897 1.13l-2.685.8.8-2.685a4.5 4.5 0 0 1 1.13-1.897L16.863 4.487Zm0 0L19.5 7.125",
      css_class: css_class,
      stroke_width: "1.5",
      **options
    )
  end

  def back_arrow_icon(css_class: "h-4 w-4", **options)
    heroicon(
      "M15.75 19.5 8.25 12l7.5-7.5",
      css_class: css_class,
      stroke_width: "2",
      **options
    )
  end

  def chevron_right_icon(css_class: "h-4 w-4", **options)
    heroicon(
      "m8.25 4.5 7.5 7.5-7.5 7.5",
      css_class: css_class,
      stroke_width: "2",
      **options
    )
  end

  def plus_icon(css_class: "h-4 w-4", **options)
    heroicon(
      "M12 4.5v15m7.5-7.5h-15",
      css_class: css_class,
      stroke_width: "2",
      **options
    )
  end

  def microphone_icon(css_class: "h-10 w-10", **options)
    heroicon(
      "M12 18.75a6 6 0 0 0 6-6v-1.5m-6 7.5a6 6 0 0 1-6-6v-1.5m6 7.5v3.75m-3.75 0h7.5M12 15.75a3 3 0 0 1-3-3V4.5a3 3 0 1 1 6 0v8.25a3 3 0 0 1-3 3Z",
      css_class: css_class,
      stroke_width: "1.5",
      **options
    )
  end

  def person_icon(css_class: "h-8 w-8", **options)
    heroicon(
      "M15.75 6a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0ZM4.501 20.118a7.5 7.5 0 0 1 14.998 0A17.933 17.933 0 0 1 12 21.75c-2.676 0-5.216-.584-7.499-1.632Z",
      css_class: css_class,
      stroke_width: "1.5",
      **options
    )
  end

  def calendar_icon(css_class: "h-3 w-3", **options)
    heroicon(
      "M6.75 3v2.25M17.25 3v2.25M3 18.75V7.5a2.25 2.25 0 0 1 2.25-2.25h13.5A2.25 2.25 0 0 1 21 7.5v11.25m-18 0A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75m-18 0v-7.5A2.25 2.25 0 0 1 5.25 9h13.5A2.25 2.25 0 0 1 21 9v9.75",
      css_class: css_class,
      stroke_width: "2",
      **options
    )
  end

  def close_icon(css_class: "h-4 w-4", **options)
    heroicon(
      "M6 18 18 6M6 6l12 12",
      css_class: css_class,
      stroke_width: "1.5",
      **options
    )
  end

  def check_circle_icon(css_class: "h-5 w-5", **options)
    heroicon(
      "M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z",
      css_class: css_class,
      stroke_width: "2",
      **options
    )
  end

  def circle_icon(css_class: "h-5 w-5", **options)
    heroicon(
      "M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z",
      css_class: css_class,
      stroke_width: "2",
      **options
    )
  end

  def spinner_icon(css_class: "h-8 w-8", **options)
    heroicon(
      "M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0 3.181 3.183a8.25 8.25 0 0 0 13.803-3.7M4.031 9.865a8.25 8.25 0 0 1 13.803-3.7l3.181 3.182M2.985 19.644l3.181-3.182",
      css_class: css_class,
      stroke_width: "1.5",
      **options
    )
  end

  def upload_icon(css_class: "h-10 w-10", **options)
    heroicon(
      "M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5m-13.5-9L12 3m0 0 4.5 4.5M12 3v13.5",
      css_class: css_class,
      stroke_width: "1.5",
      **options
    )
  end

  def download_icon(css_class: "h-4 w-4", **options)
    heroicon(
      "M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3",
      css_class: css_class,
      stroke_width: "2",
      **options
    )
  end

  def error_circle_icon(css_class: "h-8 w-8", **options)
    heroicon(
      "M12 9v3.75m9-.75a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9 3.75h.008v.008H12v-.008Z",
      css_class: css_class,
      stroke_width: "1.5",
      **options
    )
  end

  def left_arrow_icon(css_class: "h-4 w-4", **options)
    heroicon(
      "M10.5 19.5 3 12m0 0 7.5-7.5M3 12h18",
      css_class: css_class,
      stroke_width: "2",
      **options
    )
  end

  def checkmark_icon(css_class: "h-4 w-4", **options)
    heroicon(
      "m4.5 12.75 6 6 9-13.5",
      css_class: css_class,
      stroke_width: "1.5",
      **options
    )
  end

  def chat_bubble_icon(css_class: "h-6 w-6", **options)
    heroicon(
      "M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z",
      css_class: css_class,
      stroke_width: "2",
      **options
    )
  end

  def document_icon(css_class: "h-10 w-10", **options)
    heroicon(
      "M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m6.75 12H9.75m3 0H9.75m0 0H12m-2.25 0H12M6 20.25h12A2.25 2.25 0 0 0 20.25 18V6A2.25 2.25 0 0 0 18 3.75H6A2.25 2.25 0 0 0 3.75 6v12A2.25 2.25 0 0 0 6 20.25z",
      css_class: css_class,
      stroke_width: "1.5",
      **options
    )
  end

  def error_circle_filled_icon(css_class: "h-5 w-5", **options)
    tag.svg(
      tag.path(
        fill_rule: "evenodd",
        d: "M10 18a8 8 0 1 0 0-16 8 8 0 0 0 0 16zM8.28 7.22a.75.75 0 0 0-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 1 0 1.06 1.06L10 11.06l1.72 1.72a.75.75 0 1 0 1.06-1.06L11.06 10l1.72-1.72a.75.75 0 0 0-1.06-1.06L10 8.94 8.28 7.22z",
        clip_rule: "evenodd"
      ),
      xmlns: "http://www.w3.org/2000/svg",
      class: css_class,
      viewBox: "0 0 20 20",
      fill: "currentColor",
      **options
    )
  end

  private

  def heroicon(path_d, css_class:, stroke_width: "1.5", **options)
    tag.svg(
      tag.path(d: path_d, stroke_linecap: "round", stroke_linejoin: "round"),
      xmlns: "http://www.w3.org/2000/svg",
      class: css_class,
      fill: "none",
      viewBox: "0 0 24 24",
      stroke_width: stroke_width,
      stroke: "currentColor",
      **options
    )
  end
end
