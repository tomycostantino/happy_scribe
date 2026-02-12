# app/services/happy_scribe/api_error.rb
module HappyScribe
  class ApiError < StandardError
    attr_reader :status, :body

    def initialize(message = nil, status: nil, body: nil)
      @status = status
      @body = body
      super(message)
    end
  end
end
