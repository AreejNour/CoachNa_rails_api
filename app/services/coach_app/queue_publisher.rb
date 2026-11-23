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
      def publish(exchange:, routing_key:, body:)
        ensure_channel
        @returned = false
        @exchange.publish(body, routing_key: routing_key, persistent: true, mandatory: true)
        confirmed = Timeout.timeout(TIMEOUT) { @channel.wait_for_confirms }
        raise "publish not confirmed" unless confirmed
        raise "publish returned as unroutable" if @returned
      rescue StandardError
        reset
        raise
      end

      private

      def ensure_channel
        return if @channel&.open? && @connection&.open?

        reset
        @connection = Bunny.new(
          ENV.fetch("RABBITMQ_URL", "amqp://guest:guest@localhost:5672"),
          automatically_recover: true, connection_timeout: TIMEOUT, read_timeout: TIMEOUT, write_timeout: TIMEOUT
        )
        @connection.start
        @channel = @connection.create_channel
        @channel.confirm_select
        # Passive: Node declares the exchange, so a mismatch can never close this channel.
        @exchange = Bunny::Exchange.new(@channel, :direct, EXCHANGE, durable: true, passive: true)
        @exchange.on_return { |_info, _properties, _body| @returned = true }
      end

      def reset
        @connection&.close
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
