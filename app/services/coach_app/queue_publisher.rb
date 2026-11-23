require "bunny"

module CoachApp
  # Publishes to the `coachna` exchange. Node's worker owns the queues; Rails only publishes.
  module QueuePublisher
    EXCHANGE = "coachna".freeze
    MUTEX = Mutex.new

    # Publishes a persistent message and waits for the broker's confirm. Raises on failure.
    class AmqpAdapter
      def publish(exchange:, routing_key:, body:)
        channel = channel_for_publish
        channel.direct(exchange, durable: true).publish(body, routing_key: routing_key, persistent: true)
        channel.wait_for_confirms || raise("publish not confirmed")
      rescue StandardError
        reset
        raise
      end

      private

      def channel_for_publish
        @channel = nil unless @channel&.open?
        @channel ||= begin
          @connection = Bunny.new(ENV.fetch("RABBITMQ_URL", "amqp://guest:guest@localhost:5672"), automatically_recover: true)
          @connection.start
          channel = @connection.create_channel
          channel.confirm_select
          channel
        end
      end

      def reset
        @connection&.close
      rescue StandardError
        nil
      ensure
        @connection = @channel = nil
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
        @adapter || MUTEX.synchronize { @default ||= Rails.env.test? ? TestAdapter.new : AmqpAdapter.new }
      end

      def publish(routing_key:, body:)
        MUTEX.synchronize { adapter.publish(exchange: EXCHANGE, routing_key: routing_key, body: body) }
      end
    end
  end
end
