RubyLLM.configure do |config|
  config.openai_api_key = Rails.application.credentials.dig(:openai, :api_key)
  config.anthropic_api_key = Rails.application.credentials.dig(:anthropic, :api_key)
  config.default_model = Rails.application.credentials.dig(:ruby_llm, :default_model) || "claude-sonnet-4-20250514"
  config.use_new_acts_as = true

  if Rails.env.test?
    config.openai_api_key ||= "test-key"
    config.anthropic_api_key ||= "test-key"
  end
end
