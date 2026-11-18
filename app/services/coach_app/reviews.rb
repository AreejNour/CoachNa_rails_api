module CoachApp
  # The coach's view of client reviews (Milestone 23): the same set the public coach page shows
  # (status 'visible', visible photos), but all of them rather than the newest 10.
  module Reviews
    def self.list(coach)
      reviews = coach.coach_reviews.where(status: "visible").joins(:client).order(created_at: :desc, id: :desc)
                     .includes(:client, :review_photos, subscription: :coach_package)
      ReviewListJson.call(coach, reviews)
    end

    PHOTO_MIMES = { ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg", ".png" => "image/png",
                    ".webp" => "image/webp" }.freeze

    # A visible photo of a visible review of this coach: a signed URL, or the bytes. Anything else is 404.
    def self.photo(coach, photo_id)
      photo = ReviewPhoto.joins(:coach_review)
                         .find_by(id: photo_id, status: "visible",
                                  coach_reviews: { coach_id: coach.id, status: "visible" })
      raise ApiError.new(404, "not found") unless photo

      url = Storage.current.download_url(photo.storage_key, 300)
      { mime: PHOTO_MIMES.fetch(File.extname(photo.storage_key).downcase, "application/octet-stream"),
        url: url, bytes: url ? nil : Storage.current.read(photo.storage_key) }
    rescue Storage::NotFound, Storage::InvalidKey
      raise ApiError.new(404, "not found")
    end
  end
end
