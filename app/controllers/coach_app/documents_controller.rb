module CoachApp
  class DocumentsController < BaseController
    def create
      type = Input.text(params[:type])
      file = params[:file]
      Input.invalid! unless file.respond_to?(:read) && file.respond_to?(:content_type)

      render_success(DocumentJson.call(Documents.add(current_coach, type, file)), status: :created)
    end

    def destroy
      Documents.remove(current_coach, params[:id])
      render_success({})
    end

    def file
      document = Documents.find_owned!(current_coach, params[:id])
      download = Documents.download(document)

      # These include ID photos, so no copy should stay in a cache.
      response.headers["Cache-Control"] = "no-store"
      if download[:url]
        redirect_to download[:url], allow_other_host: true
      else
        send_data download[:bytes], type: document.mime_type, disposition: "inline"
      end
    end
  end
end
