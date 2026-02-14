# AI model configuration — used by AI processing jobs and tools.
# Override via environment variables for different environments.
Rails.application.config.ai = ActiveSupport::OrderedOptions.new
Rails.application.config.ai.default_model = ENV.fetch("AI_MODEL", "claude-sonnet-4-20250514")
Rails.application.config.ai.embedding_model = ENV.fetch("AI_EMBEDDING_MODEL", "text-embedding-3-small")
