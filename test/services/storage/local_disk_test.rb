require "test_helper"

class Storage::LocalDiskTest < ActiveSupport::TestCase
  BASE = Rails.root.join("tmp/local-disk-test").to_s

  setup { FileUtils.mkdir_p(BASE) }
  teardown { FileUtils.rm_rf(BASE); FileUtils.rm_rf("#{BASE}-other") }

  def driver = Storage::LocalDisk.new(BASE)

  test "put then read returns the same bytes, including non-UTF-8 ones" do
    bytes = "\xFF\xD8\xFF\x00\x01binary".b

    driver.put("coaches/c1/certificate/a.jpg", bytes, mime_type: "image/jpeg")

    assert_equal bytes, driver.read("coaches/c1/certificate/a.jpg")
    assert_equal Encoding::BINARY, driver.read("coaches/c1/certificate/a.jpg").encoding
  end

  test "put creates missing folders and leaves no temporary file" do
    driver.put("a/b/c/d.png", "x", mime_type: "image/png")

    assert_equal [ "d.png" ], Dir.children(File.join(BASE, "a/b/c"))
  end

  test "delete removes the file and ignores a missing one" do
    driver.put("a.jpg", "x", mime_type: "image/jpeg")

    assert_nil driver.delete("a.jpg")
    assert_not File.exist?(File.join(BASE, "a.jpg"))
    assert_nil driver.delete("a.jpg")
  end

  test "read of a missing file raises NotFound" do
    assert_raises(Storage::NotFound) { driver.read("missing.jpg") }
  end

  [ "../x", "a/../../x", "/etc/passwd", "" ].each do |key|
    test "a key that escapes the base folder is refused: #{key.inspect}" do
      assert_raises(Storage::InvalidKey) { driver.put(key, "x", mime_type: "image/png") }
      assert_raises(Storage::InvalidKey) { driver.read(key) }
      assert_raises(Storage::InvalidKey) { driver.delete(key) }
    end
  end

  test "a sibling folder sharing the base's prefix is refused" do
    FileUtils.mkdir_p("#{BASE}-other")

    assert_raises(Storage::InvalidKey) { driver.read("../local-disk-test-other/f") }
  end

  test "download_url is nil, so the API streams the file" do
    assert_nil driver.download_url("a.jpg", 300)
  end
end
