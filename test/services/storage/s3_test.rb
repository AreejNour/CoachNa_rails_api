require "test_helper"

class Storage::S3Test < ActiveSupport::TestCase
  def driver(endpoint: nil)
    Storage::S3.new(
      bucket: "coachna", region: "auto", endpoint: endpoint,
      access_key_id: "id", secret_access_key: "secret", stub_responses: true
    )
  end

  test "put sends the bucket, key, body and content type" do
    s3 = driver

    assert_nil s3.put("coaches/c1/a.jpg", "bytes", mime_type: "image/jpeg")

    request = s3.client.api_requests.last
    assert_equal :put_object, request[:operation_name]
    assert_equal "coachna", request[:params][:bucket]
    assert_equal "coaches/c1/a.jpg", request[:params][:key]
    assert_equal "image/jpeg", request[:params][:content_type]
  end

  test "read returns the body" do
    s3 = driver
    s3.client.stub_responses(:get_object, { body: "bytes" })

    assert_equal "bytes", s3.read("a.jpg")
  end

  test "a missing object raises NotFound" do
    s3 = driver
    s3.client.stub_responses(:get_object, "NoSuchKey")

    assert_raises(Storage::NotFound) { s3.read("a.jpg") }
  end

  test "delete removes the object" do
    s3 = driver

    assert_nil s3.delete("a.jpg")

    assert_equal :delete_object, s3.client.api_requests.last[:operation_name]
  end

  test "download_url is signed, for the key, and expires" do
    url = driver.download_url("coaches/c1/a.jpg", 300)

    assert_includes url, "coaches/c1/a.jpg"
    assert_includes url, "X-Amz-Signature"
    assert_includes url, "X-Amz-Expires=300"
  end

  test "an endpoint uses path-style URLs, like the Node API" do
    url = driver(endpoint: "https://r2.example.com").download_url("a.jpg", 300)

    assert url.start_with?("https://r2.example.com/coachna/a.jpg"), url
  end
end
