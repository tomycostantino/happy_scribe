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

# Populate the in-memory model registry from configured providers so that
# model resolution (e.g. "claude-sonnet-4-20250514") works on first request.
# The bundled models.json may fail to load in some environments (Docker/production).
Rails.application.config.after_initialize do
  next if Rails.env.test?

  if RubyLLM.models.all.empty?
    Rails.logger.info "RubyLLM: model registry empty, refreshing from providers..."
    RubyLLM.models.refresh!
    Rails.logger.info "RubyLLM: loaded #{RubyLLM.models.all.count} models"
  end
end
