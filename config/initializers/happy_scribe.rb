Rails.application.config.happy_scribe = ActiveSupport::OrderedOptions.new
Rails.application.config.happy_scribe.api_key = Rails.application.credentials.dig(:happy_scribe, :api_key)
Rails.application.config.happy_scribe.organization_id = Rails.application.credentials.dig(:happy_scribe, :organization_id)
