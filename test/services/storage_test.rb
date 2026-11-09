require "test_helper"

class StorageTest < ActiveSupport::TestCase
  def with_env(values)
    saved = values.keys.to_h { |key| [ key, ENV[key] ] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
    Storage.reset!
  end

  test "local is the default driver" do
    with_env("STORAGE_DRIVER" => nil, "LOCAL_STORAGE_DIR" => "tmp/test-storage") do
      Storage.reset!

      assert_instance_of Storage::LocalDisk, Storage.current
    end
  end

  test "current is kept between calls" do
    Storage.reset!

    assert_same Storage.current, Storage.current
  end

  test "S3 is chosen by STORAGE_DRIVER" do
    with_env("STORAGE_DRIVER" => "s3", "S3_BUCKET" => "b", "S3_REGION" => "auto", "S3_ACCESS_KEY_ID" => "i", "S3_SECRET_ACCESS_KEY" => "s") do
      Storage.reset!

      assert_instance_of Storage::S3, Storage.current
    end
  end

  test "an unknown driver is refused" do
    with_env("STORAGE_DRIVER" => "ftp") do
      Storage.reset!

      assert_raises(Storage::NotConfigured) { Storage.current }
    end
  end

  test "a relative folder is resolved from the Rails root" do
    assert_equal Rails.root.join("tmp/test-storage").to_s, Storage.local_dir(env: "test")
  end

  test "no folder set is refused, rather than storing files somewhere Node won't look" do
    with_env("LOCAL_STORAGE_DIR" => nil) do
      error = assert_raises(Storage::NotConfigured) { Storage.local_dir(env: "development") }

      assert_includes error.message, "CoachNa_api/.storage"
    end
  end

  test "in development, a folder that doesn't exist is refused and names Node's folder" do
    with_env("LOCAL_STORAGE_DIR" => "../no-such-folder/.storage") do
      error = assert_raises(Storage::NotConfigured) { Storage.local_dir(env: "development") }

      assert_includes error.message, "CoachNa_api/.storage"
    end
  end
end
