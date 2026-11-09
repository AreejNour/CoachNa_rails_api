require "aws-sdk-s3"

module Storage
  class S3
    attr_reader :client

    def initialize(bucket:, region:, endpoint:, access_key_id:, secret_access_key:, stub_responses: false)
      @bucket = bucket
      options = {
        region: region,
        credentials: Aws::Credentials.new(access_key_id, secret_access_key),
        force_path_style: endpoint.present?,
        stub_responses: stub_responses
      }
      options[:endpoint] = endpoint if endpoint
      @client = Aws::S3::Client.new(options)
    end

    def put(key, bytes, mime_type:)
      client.put_object(bucket: @bucket, key: key, body: bytes, content_type: mime_type)
      nil
    end

    def delete(key)
      client.delete_object(bucket: @bucket, key: key)
      nil
    end

    def read(key)
      client.get_object(bucket: @bucket, key: key).body.read
    rescue Aws::S3::Errors::NoSuchKey
      raise NotFound, key
    end

    def download_url(key, ttl_seconds)
      Aws::S3::Presigner.new(client: client).presigned_url(:get_object, bucket: @bucket, key: key, expires_in: ttl_seconds)
    end
  end
end
