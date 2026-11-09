module Storage
  class LocalDisk
    def initialize(base_dir)
      @base_dir = File.expand_path(base_dir)
    end

    # Written to a temporary name and renamed, so the Node API never reads half a file.
    def put(key, bytes, mime_type:)
      path = full_path(key)
      FileUtils.mkdir_p(File.dirname(path))
      temporary = "#{path}.#{SecureRandom.hex(8)}.tmp"
      begin
        File.binwrite(temporary, bytes)
        File.rename(temporary, path)
      ensure
        FileUtils.rm_f(temporary)
      end
      nil
    end

    def delete(key)
      FileUtils.rm_f(full_path(key))
      nil
    end

    def read(key)
      File.binread(full_path(key))
    rescue Errno::ENOENT, Errno::EISDIR
      raise NotFound, key
    end

    # The API streams local files itself.
    def download_url(_key, _ttl_seconds)
      nil
    end

    private

    def full_path(key)
      path = File.expand_path(key.to_s, @base_dir)
      raise InvalidKey, key unless path.start_with?("#{@base_dir}/")

      path
    end
  end
end
