# Development uses the database shared with the Node API, and its data must survive anything
# Rails does. Only a database named *_test may be reset.
module SharedDbGuard
  class Unsafe < StandardError; end

  def self.assert_safe!(database_name)
    return if database_name.to_s.end_with?("_test")

    raise Unsafe, "Refusing to reset #{database_name.inspect}: only a database named *_test may be reset, " \
      "because development shares its database with the Node API."
  end
end
