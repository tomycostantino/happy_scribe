# config/initializers/happy_scribe.rb
Rails.application.config.happy_scribe = ActiveSupport::OrderedOptions.new
Rails.application.config.happy_scribe.api_key = ENV["HAPPY_SCRIBE_API_KEY"]
Rails.application.config.happy_scribe.organization_id = ENV["HAPPY_SCRIBE_ORGANIZATION_ID"]
