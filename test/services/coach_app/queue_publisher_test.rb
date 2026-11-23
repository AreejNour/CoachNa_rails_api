require "test_helper"

# Exercises the real adapter path (no adapter= override) against a fake Bunny.
class CoachApp::QueuePublisherTest < ActiveSupport::TestCase
  class FakeChannel
    attr_accessor :confirms, :hangs
    def initialize = @confirms = true
    def open? = true
    def confirm_select = nil
    def wait_for_confirms = (sleep(5) if hangs; confirms)
  end

  class FakeSession
    attr_reader :channel, :closed
    def initialize = (@channel = FakeChannel.new)
    def start = self
    def open? = !@closed
    def create_channel = channel
    def close = @closed = true
  end

  class FakeExchange
    attr_reader :published
    def initialize(unroutable: false) = (@published = []; @unroutable = unroutable)
    def on_return(&block) = @on_return = block
    def publish(body, **options)
      @published << [ body, options ]
      @on_return.call({}, {}, body) if @unroutable
    end
  end

  setup do
    @saved_default = CoachApp::QueuePublisher.instance_variable_get(:@default)
    @saved = CoachApp::QueuePublisher.instance_variable_get(:@adapter)
    CoachApp::QueuePublisher.adapter = nil
    CoachApp::QueuePublisher.instance_variable_set(:@default, nil)
    # Rails.env.test? would pick the test adapter, so force the real one.
    CoachApp::QueuePublisher.instance_variable_set(:@default, CoachApp::QueuePublisher::AmqpAdapter.new)
    @session = FakeSession.new
    @exchange = FakeExchange.new
  end

  teardown do
    CoachApp::QueuePublisher.instance_variable_set(:@default, @saved_default)
    CoachApp::QueuePublisher.adapter = @saved
  end

  def with_fakes(exchange: @exchange, &block)
    session = @session
    swap(Bunny, :new, ->(*_, **_) { session }) { swap(Bunny::Exchange, :new, ->(*_, **_) { exchange }, &block) }
  end

  # Replaces klass.new for the block (minitest 6 has no #stub).
  def swap(klass, name, replacement)
    original = klass.method(name)
    klass.define_singleton_method(name) { |*args, **kw| replacement.call(*args, **kw) }
    yield
  ensure
    klass.define_singleton_method(name, original)
  end

  test "publishes persistent and mandatory through the default adapter without a deadlock" do
    with_fakes { CoachApp::QueuePublisher.publish(routing_key: "push", body: "{}") }

    assert_equal [ [ "{}", { routing_key: "push", persistent: true, mandatory: true } ] ], @exchange.published
  end

  test "an unconfirmed publish raises" do
    @session.channel.confirms = false

    with_fakes do
      assert_raises(RuntimeError) { CoachApp::QueuePublisher.publish(routing_key: "push", body: "{}") }
    end
    assert @session.closed
  end

  test "a returned (unroutable) message raises" do
    exchange = FakeExchange.new(unroutable: true)

    with_fakes(exchange: exchange) do
      assert_raises(RuntimeError) { CoachApp::QueuePublisher.publish(routing_key: "push", body: "{}") }
    end
  end

  test "a hanging confirm raises within the bound, resets the session, then cools down" do
    CoachApp::QueuePublisher.instance_variable_set(:@default, CoachApp::QueuePublisher::AmqpAdapter.new(timeout: 0.2))
    @session.channel.hangs = true

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    with_fakes do
      assert_raises(Timeout::Error) { CoachApp::QueuePublisher.publish(routing_key: "push", body: "{}") }
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 2
      assert @session.closed

      error = assert_raises(RuntimeError) { CoachApp::QueuePublisher.publish(routing_key: "push", body: "{}") }
      assert_match(/cooling down/, error.message)
    end
  end

  test "the cooldown fails fast without extending, then expires and a real attempt happens" do
    adapter = CoachApp::QueuePublisher::AmqpAdapter.new
    clock = 100.0
    adapter.define_singleton_method(:now) { clock }
    CoachApp::QueuePublisher.instance_variable_set(:@default, adapter)
    @session.channel.confirms = false

    with_fakes do
      assert_raises(RuntimeError) { CoachApp::QueuePublisher.publish(routing_key: "push", body: "{}") }
      attempts = @exchange.published.size

      clock = 104.0
      error = assert_raises(RuntimeError) { CoachApp::QueuePublisher.publish(routing_key: "push", body: "{}") }
      assert_match(/cooling down/, error.message)
      assert_equal attempts, @exchange.published.size

      # Still 5 s after the first failure (not the second call), so the window has expired.
      clock = 105.5
      @session.channel.confirms = true
      CoachApp::QueuePublisher.publish(routing_key: "push", body: "{}")
      assert_equal attempts + 1, @exchange.published.size
    end
  end
end
