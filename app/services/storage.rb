# Files shared with the Node API, which serves coach photos to the client app. Both backends must
# use the same folder or bucket, with the same env names.
module Storage
  class NotFound < StandardError; end
  class InvalidKey < StandardError; end
  class NotConfigured < StandardError; end

  NODE_FOLDER_HINT = "Set LOCAL_STORAGE_DIR to the Node API's storage folder, CoachNa_api/.storage, " \
    "or uploads will work here but clients won't see the photos."

  def self.current
    @current ||= build
  end

  def self.reset!
    @current = nil
  end

  def self.local_dir(env: Rails.env.to_s)
    value = ENV["LOCAL_STORAGE_DIR"].presence
    raise NotConfigured, "LOCAL_STORAGE_DIR is not set. #{NODE_FOLDER_HINT}" unless value

    dir = File.expand_path(value, Rails.root)
    if env == "development" && !Dir.exist?(dir)
      raise NotConfigured, "#{dir} doesn't exist. #{NODE_FOLDER_HINT}"
    end
    dir
  end

  def self.build
    case ENV.fetch("STORAGE_DRIVER", "local")
    when "local" then LocalDisk.new(local_dir)
    when "s3"
      S3.new(
        bucket: ENV.fetch("S3_BUCKET"),
        region: ENV.fetch("S3_REGION", "auto"),
        endpoint: ENV["S3_ENDPOINT"].presence,
        access_key_id: ENV.fetch("S3_ACCESS_KEY_ID"),
        secret_access_key: ENV.fetch("S3_SECRET_ACCESS_KEY")
      )
    else
      raise NotConfigured, "Unknown STORAGE_DRIVER: #{ENV["STORAGE_DRIVER"]}"
    end
  end
  private_class_method :build
end
