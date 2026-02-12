# app/services/happy_scribe/transcription_failed_error.rb
module HappyScribe
  class TranscriptionFailedError < ApiError
    attr_reader :reason

    def initialize(message = nil, reason: nil, **kwargs)
      @reason = reason
      super(message, **kwargs)
    end
  end
end
