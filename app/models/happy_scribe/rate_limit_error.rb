module HappyScribe
  class RateLimitError < ApiError
    attr_reader :retry_in

    def initialize(message = nil, retry_in: nil, **kwargs)
      @retry_in = retry_in
      super(message, **kwargs)
    end
  end
end
