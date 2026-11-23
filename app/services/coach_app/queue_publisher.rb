require "bunny"
require "timeout"

module CoachApp
  # Publishes to the `coachna` exchange. Node's worker owns the exchange and queues; Rails only
  # publishes. Every network step is bounded, because this runs inside a request.
  module QueuePublisher
    EXCHANGE = "coachna".freeze
    TIMEOUT = 3
    MUTEX = Mutex.new

    # Publishes a persistent, mandatory message and waits for the broker's confirm. Raises on a
    # timeout, an unconfirmed publish or an unroutable (returned) message.
    class AmqpAdapter
      COOLDOWN = 5

      def initialize(timeout: TIMEOUT)
        @timeout = timeout
      end

      def publish(exchange:, routing_key:, body:)
        # After a failure, skip the broker for a moment so threads don't queue behind a dead one.
        # The rows stay unpublished and Node's sweeper sends them. This check is outside the
        # rescued attempt, so a cooling-down call neither extends the window nor resets.
        raise "broker unavailable (cooling down)" if @down_until && now < @down_until

        attempt(exchange: exchange, routing_key: routing_key, body: body)
      end

      private

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      def attempt(exchange:, routing_key:, body:)
        ensure_channel
        @returned = false
        @exchange.publish(body, routing_key: routing_key, persistent: true, mandatory: true)
        # Timeout interrupts the wait at an arbitrary point; that is safe only because the
        # rescue below always calls reset, which drops the channel and connection.
        confirmed = Timeout.timeout(@timeout) { @channel.wait_for_confirms }
        raise "publish not confirmed" unless confirmed
        raise "publish returned as unroutable" if @returned
      rescue StandardError
        @down_until = now + COOLDOWN
        reset
        raise
      end

      def ensure_channel
        return if @channel&.open? && @connection&.open?

        reset
        @connection = Bunny.new(
          ENV.fetch("RABBITMQ_URL", "amqp://guest:guest@localhost:5672"),
          automatically_recover: false, connection_timeout: @timeout, read_timeout: @timeout,
          write_timeout: @timeout, continuation_timeout: (@timeout * 1000).to_i
        )
        @connection.start
        @channel = @connection.create_channel
        @channel.confirm_select
        # Passive: Node declares the exchange, so a mismatch can never close this channel.
        @exchange = Bunny::Exchange.new(@channel, :direct, EXCHANGE, durable: true, passive: true)
        @exchange.on_return { |_info, _properties, _body| @returned = true }
      end

      def reset
        connection = @connection
        Timeout.timeout(@timeout) { connection&.close }
      rescue StandardError
        nil
      ensure
        @connection = @channel = @exchange = nil
      end
    end

    # Records publishes instead of sending them; used in tests.
    class TestAdapter
      attr_reader :published
      attr_accessor :fail_with, :fail_times

      def initialize
        @published = []
      end

      def publish(exchange:, routing_key:, body:)
        if fail_with && (fail_times.nil? || fail_times.positive?)
          self.fail_times -= 1 if fail_times
          raise fail_with
        end
        @published << { exchange: exchange, routing_key: routing_key, body: body }
      end
    end

    class << self
      attr_writer :adapter

      def adapter
        MUTEX.synchronize { current_adapter }
      end

      def publish(routing_key:, body:)
        MUTEX.synchronize { current_adapter.publish(exchange: EXCHANGE, routing_key: routing_key, body: body) }
      end

      private

      # Callers hold MUTEX (it isn't reentrant).
      def current_adapter
        @adapter || (@default ||= Rails.env.test? ? TestAdapter.new : AmqpAdapter.new)
      end
    end
  end
end
