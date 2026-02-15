module FlashHelper
  def flash_messages
    safe_join([ flash_alert, flash_notice ].compact)
  end

  private

  def flash_alert
    return unless flash[:alert]

    tag.div(flash[:alert], class: "mb-4 rounded-md bg-red-50 p-3 text-sm text-red-700")
  end

  def flash_notice
    return unless flash[:notice]

    tag.div(flash[:notice], class: "mb-4 rounded-md bg-green-50 p-3 text-sm text-green-700")
  end
end
