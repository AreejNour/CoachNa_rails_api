module Admin
  class CoachesController < BaseController
    # The review list: coaches waiting for approval, newest submission first.
    def index
      @coaches = Coach.where(status: "pending_review").order(profile_submitted_at: :desc)
    end

    def show
      @coach = Coach.find(params[:id])
      @documents = @coach.coach_documents.order(:type)
    end

    # Streams one of a coach's documents (ID/certificate images) for review. No-store, since
    # these are sensitive; only a signed-in admin reaches it (require_admin in the base).
    def document
      coach = Coach.find(params[:id])
      doc = coach.coach_documents.find(params[:document_id])
      download = CoachApp::Documents.download(doc)
      response.headers["Cache-Control"] = "no-store"
      if download[:url]
        redirect_to download[:url], allow_other_host: true
      else
        send_data download[:bytes], type: doc.mime_type, disposition: "inline"
      end
    rescue ActiveRecord::RecordNotFound, ApiError
      head :not_found
    end
  end
end
