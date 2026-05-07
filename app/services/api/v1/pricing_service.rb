module Api::V1
  class PricingService < BaseService
    UPDATE_RATES_LOCK_KEY = 'update_rates'.freeze
    UPDATE_RATES_LOCK_TTL = 5.seconds.freeze
    RATE_STATUS_KEY = 'rate_status:updated'.freeze
    RATE_STATUS_TTL = (4.minutes + 55.seconds).freeze
    RATE_TTL = (4.minutes + 58.seconds).freeze

    def initialize(period:, hotel:, room:)
      @period = period
      @hotel = hotel
      @room = room
    end

    def run
      # Retrieve room rate from cache.
      room_rate_key = build_rate_cache_key(hotel: @hotel, period: @period, room: @room)
      @result = Rails.cache.read(room_rate_key)

      if @result.present?
        send_cache_metric('hit')
        return @result
      end

      send_cache_metric('miss')

      # If rate is not cached yet, try to retrieve rates from internal service and update cache.
      update_all_rates

      # Use rate if found during update or retrieve from updated cache.
      @result ||= Rails.cache.read(room_rate_key)

      raise Errors::NotFoundError.new('Rate is not found.') if invalid_rate?(@result)

      @result
    rescue => e
      Rails.logger.error({
        level: 'error',
        tags: ['dynamic_pricing', 'pricing_service'],
        error: e.class.name,
        message: e.message,
        backtrace: e.backtrace&.take(5)&.join("\n"),
        track_id: room_rate_key,
        request_id: Thread.current[:request_id]
      }.to_json)
      raise
    end

    private

    def build_rate_cache_key(hotel:, period:, room:)
      "#{hotel}:#{period}:#{room}:rate"
    end

    def invalid_rate?(rate)
      rate.blank? || rate.to_i == 0
    end

    def update_all_rates
      Lock.with_lock(UPDATE_RATES_LOCK_KEY, UPDATE_RATES_LOCK_TTL) do
        # Skip rates retrieval & cache update if values are recently updated.
        already_updated = Rails.cache.read(RATE_STATUS_KEY).present?
        return if already_updated

        # Retrieve all rates.
        rates = RateApiClient.get_all_rates&.dig(:rates) || []
        # TODO: Consider skipping marking status as updated when got invalid response.
        # return if rates.blank?
        if rates.blank?
          Rails.logger.warn({
            level: 'warn',
            tags: ['dynamic_pricing', 'pricing_service', 'update_all_rates'],
            message: 'Successfully get all rates but rates is empty.',
            request_id: Thread.current[:request_id]
          }.to_json)
        end

        # Update all rates in cache.
        rates.each do |rate|
          rate_num = rate[:rate].to_i
          key = build_rate_cache_key(hotel: rate[:hotel], period: rate[:period], room: rate[:room])

          # Skip cache update if rate is not valid.
          if invalid_rate?(rate_num)
            Rails.logger.warn({
              level: 'warn',
              tags: ['dynamic_pricing', 'pricing_service', 'update_all_rates'],
              message: "Successfully get all rates but rate value is invalid: #{rate_num}",
              track_id: key,
              request_id: Thread.current[:request_id]
            }.to_json)
            next
          end

          res = Rails.cache.write(key, rate_num, expires_in: RATE_TTL)

          if rate[:hotel] == @hotel && rate[:period] == @period && rate[:room] == @room
            @result = rate_num
          end
        end

        # Mark rate update status as recently updated.
        Rails.cache.write(RATE_STATUS_KEY, 1, expires_in: RATE_STATUS_TTL)
      end
    end

    # TODO: Sending metric using logger for now, need to replace with actual monitoring tool.
    def send_cache_metric(cache_hit_status)
      Rails.logger.info({
        metric: 'cache_access',
        service: 'dynamic_pricing',
        class: 'pricing_service',
        status: cache_hit_status
      }.to_json)
    rescue
      nil
    end
  end
end
