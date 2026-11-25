module Admin
  class ReviewsController < BaseController
    PHOTO_MIMES = { ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg", ".png" => "image/png",
                    ".webp" => "image/webp" }.freeze

    # Moderation queue: all reviews awaiting admin decision, oldest first.
    def index
      @reviews = CoachReview.where(status: "pending").order(created_at: :asc)
                             .includes(:coach, :client, :review_photos)
    end

    def show
      @review = CoachReview.find(params[:id])
    end

    def approve
      decision(:approve)
    end

    def reject
      decision(:reject)
    end

    # Streams one review photo for admin inspection. No visibility filter — admins
    # can view pending photos. Mirrors CoachApp::Reviews.photo but without the
    # `visible` guard. Cache-Control: no-store (sensitive media).
    def photo
      photo = CoachReview.find(params[:id]).review_photos.find(params[:photo_id])
      response.headers["Cache-Control"] = "no-store"
      url = Storage.current.download_url(photo.storage_key, 300)
      if url
        redirect_to url, allow_other_host: true
      else
        mime = PHOTO_MIMES.fetch(File.extname(photo.storage_key).downcase, "application/octet-stream")
        send_data Storage.current.read(photo.storage_key), type: mime, disposition: "inline"
      end
    rescue Storage::NotFound, Storage::InvalidKey
      head :not_found
    end

    private

    def decision(action)
      review = CoachReview.find(params[:id])
      case action
      when :approve
        Admin::ReviewDecision.approve!(review: review, admin: current_admin)
        flash[:notice] = "Review approved."
      when :reject
        Admin::ReviewDecision.reject!(review: review, admin: current_admin)
        flash[:notice] = "Review rejected."
      end
      redirect_to admin_review_path(review)
    rescue Admin::ReviewDecision::Error => e
      redirect_to admin_review_path(CoachReview.find(params[:id])), flash: { alert: e.message }
    end
  end
end
