# Handles creating user messages and enqueuing AI responses.
#
# Separates the synchronous part (creating the user message, which the
# controller can render immediately) from the async part (getting the
# AI response via background job).
module Chat::Respondable
  extend ActiveSupport::Concern

  # Creates the user message and enqueues a background job to generate
  # the AI response. Returns the persisted user message so the controller
  # can render it immediately (instant feedback).
  def send_message(content)
    message = create_user_message(content)
    ChatResponseJob.perform_later(id)
    message
  end
end
