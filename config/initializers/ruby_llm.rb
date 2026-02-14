RubyLLM.configure do |config|
  config.openai_api_key = ENV["OPENAI_API_KEY"]
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
  config.default_model = "claude-sonnet-4-20250514"
  config.use_new_acts_as = true

  if Rails.env.test?
    config.openai_api_key ||= "test-key"
    config.anthropic_api_key ||= "test-key"
  end
end
