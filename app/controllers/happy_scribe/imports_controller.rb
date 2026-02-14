module HappyScribe
  class ImportsController < ApplicationController
    def index
      client = HappyScribe::Client.new
      response = client.list_transcriptions(page: params[:page])
      @transcriptions = response["results"] || []
      @next_page_url = response.dig("_links", "next", "url")

      # Filter out transcriptions already imported locally
      imported_ids = Transcript.where(happyscribe_id: @transcriptions.map { |t| t["id"] }).pluck(:happyscribe_id)
      @transcriptions.each { |t| t["already_imported"] = imported_ids.include?(t["id"]) }
    rescue HappyScribe::ApiError => e
      @transcriptions = []
      @error = "Could not load transcriptions from HappyScribe: #{e.message}"
    end

    def create
      happyscribe_id = params[:happyscribe_id]

      if Transcript.exists?(happyscribe_id: happyscribe_id)
        redirect_to happy_scribe_imports_path, alert: "This transcription has already been imported."
        return
      end

      HappyScribe::Transcription::ImportJob.perform_later(Current.user.id, happyscribe_id: happyscribe_id)
      redirect_to meetings_path, notice: "Import started. The transcription will appear shortly."
    end
  end
end
