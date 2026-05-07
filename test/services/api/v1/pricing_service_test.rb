require 'test_helper'

class PricingServiceTest < ActiveSupport::TestCase
  def setup
    @period = 'Summer'
    @hotel = 'FloatingPointResort'
    @room   = 'SingletonRoom'

    @room_rate = 1_000
    @room_cache_key = 'FloatingPointResort:Summer:SingletonRoom:rate'
    @test_ttl = 10.seconds

    @all_rates = {
      rates: [
        {
          period: 'Summer',
          hotel: 'FloatingPointResort',
          room: 'SingletonRoom',
          rate: @room_rate
        },
        {
          period: 'Summer',
          hotel: 'FloatingPointResort',
          room: 'BooleanTwin',
          rate: 1_500
        },
        {
          period: 'Summer',
          hotel: 'RecursionRetreat',
          room: 'SingletonRoom',
          rate: 1_750
        },
        {
          period: 'Autumn',
          hotel: 'FloatingPointResort',
          room: 'SingletonRoom',
          rate: 2_000
        }
      ]
    }.with_indifferent_access

    @service = Api::V1::PricingService.new(
      period: @period,
      hotel: @hotel,
      room: @room
    )

    @logs = []

    Rails.cache.clear
  end

  def test_cache_hit_returns_cached_value_and_send_hit_metric
    Rails.cache.write(@room_cache_key, @room_rate, expires_in: @test_ttl)

    Rails.logger.stub(:info, ->(msg) { @logs << msg }) do
      Lock.stub(:with_lock, true) do
        result = @service.run

        assert_equal @room_rate, result
        assert_equal 1, @logs.length

        parsed_log = JSON.parse(@logs.first)
        assert_equal 'hit', parsed_log['status']
      end
    end

    Rails.cache.delete(@room_cache_key)
  end

  def test_cache_miss_update_all_rates
    cache_read_calls = 0
    original_cache_read = Rails.cache.method(:read)

    Rails.logger.stub(:info, ->(msg) { @logs << msg }) do
      RateApiClient.stub(:get_all_rates, @all_rates) do
        Lock.stub(:with_lock, true) do
          Rails.cache.stub(:read, lambda { |key, *args|
            cache_read_calls += 1 if key == @room_cache_key
            original_cache_read.call(key, *args)
          }) do
            result = @service.run

            assert_equal @room_rate, result
            assert_equal 1, @logs.length

            parsed_log = JSON.parse(@logs.first)
            assert_equal 'miss', parsed_log['status']

            # Room rate cache read only called once during initial check.
            assert_equal 1, cache_read_calls

            # All rates are stored in cache.
            assert_equal 1, Rails.cache.read(Api::V1::PricingService::RATE_STATUS_KEY)
            assert_equal 1_000, Rails.cache.read('FloatingPointResort:Summer:SingletonRoom:rate')
            assert_equal 1_500, Rails.cache.read('FloatingPointResort:Summer:BooleanTwin:rate')
            assert_equal 1_750, Rails.cache.read('RecursionRetreat:Summer:SingletonRoom:rate')
            assert_equal 2_000, Rails.cache.read('FloatingPointResort:Autumn:SingletonRoom:rate')
          end
        end
      end
    end

    Rails.cache.clear
  end

  def test_cache_miss_update_all_rates_string
    cache_read_calls = 0
    original_cache_read = Rails.cache.method(:read)

    @all_rates = {
      rates: [
        {
          period: 'Summer',
          hotel: 'FloatingPointResort',
          room: 'SingletonRoom',
          rate: '1000'
        },
        {
          period: 'Summer',
          hotel: 'FloatingPointResort',
          room: 'BooleanTwin',
          rate: '1500'
        },
        {
          period: 'Summer',
          hotel: 'RecursionRetreat',
          room: 'SingletonRoom',
          rate: '1750'
        },
        {
          period: 'Autumn',
          hotel: 'FloatingPointResort',
          room: 'SingletonRoom',
          rate: '2000'
        }
      ]
    }.with_indifferent_access

    Rails.logger.stub(:info, ->(msg) { @logs << msg }) do
      RateApiClient.stub(:get_all_rates, @all_rates) do
        Lock.stub(:with_lock, true) do
          Rails.cache.stub(:read, lambda { |key, *args|
            cache_read_calls += 1 if key == @room_cache_key
            original_cache_read.call(key, *args)
          }) do
            result = @service.run

            assert_equal @room_rate, result
            assert_equal 1, @logs.length

            parsed_log = JSON.parse(@logs.first)
            assert_equal 'miss', parsed_log['status']

            # Room rate cache read only called once during initial check.
            assert_equal 1, cache_read_calls

            # All rates are stored in cache.
            assert_equal 1, Rails.cache.read(Api::V1::PricingService::RATE_STATUS_KEY)
            assert_equal 1_000, Rails.cache.read('FloatingPointResort:Summer:SingletonRoom:rate')
            assert_equal 1_500, Rails.cache.read('FloatingPointResort:Summer:BooleanTwin:rate')
            assert_equal 1_750, Rails.cache.read('RecursionRetreat:Summer:SingletonRoom:rate')
            assert_equal 2_000, Rails.cache.read('FloatingPointResort:Autumn:SingletonRoom:rate')
          end
        end
      end
    end

    Rails.cache.clear
  end

  def test_cache_miss_rates_already_updated
    get_all_rates_called = false
    cache_read_calls = 0
    original_cache_read = Rails.cache.method(:read)

    Rails.logger.stub(:info, ->(msg) { @logs << msg }) do
      RateApiClient.stub(:get_all_rates, proc {
        get_all_rates_called = true
      }) do
        Lock.stub(:with_lock, lambda { |*args|
          Rails.cache.write(Api::V1::PricingService::RATE_STATUS_KEY, 1, expires_in: @test_ttl - 1.second)
          Rails.cache.write('FloatingPointResort:Summer:SingletonRoom:rate', 1_000, expires_in: @test_ttl)
          Rails.cache.write('FloatingPointResort:Summer:BooleanTwin:rate', 1_500, expires_in: @test_ttl)
          Rails.cache.write('RecursionRetreat:Summer:SingletonRoom:rate', 1_750, expires_in: @test_ttl)
          Rails.cache.write('FloatingPointResort:Autumn:SingletonRoom:rate', 2_000, expires_in: @test_ttl)
          true
        }) do
          Rails.cache.stub(:read, lambda { |key, *args|
            cache_read_calls += 1 if key == @room_cache_key
            original_cache_read.call(key, *args)
          }) do
            result = @service.run

            assert_equal @room_rate, result
            assert_equal 1, @logs.length

            parsed_log = JSON.parse(@logs.first)
            assert_equal 'miss', parsed_log['status']

            # Room rate cache read twice:
            # - For initial check
            # - For retrieving recently updated cache
            assert_equal 2, cache_read_calls

            assert_equal false, get_all_rates_called
          end
        end
      end
    end

    Rails.cache.clear
  end

  def test_cache_miss_lock_timeout
    get_all_rates_called = false

    Rails.logger.stub(:error, ->(msg) { @logs << msg }) do
      Rails.logger.stub(:info, ->(msg) { @logs << msg }) do
        RateApiClient.stub(:get_all_rates, proc {
          get_all_rates_called = true
        }) do
          Lock.stub(:with_lock, ->(*) {
            raise Errors::LockTimeoutError
          }) do
            assert_raises(Errors::LockTimeoutError) do
              result = @service.run
            end

            assert_equal 2, @logs.length

            parsed_first_log = JSON.parse(@logs.first)
            assert_equal 'miss', parsed_first_log['status']

            assert_equal false, get_all_rates_called
          end
        end
      end
    end
  end

  def test_cache_miss_connection_error
    Rails.logger.stub(:error, ->(msg) { @logs << msg }) do
      Rails.logger.stub(:info, ->(msg) { @logs << msg }) do
        RateApiClient.stub(:get_all_rates, ->(*) {
          raise Errors::ConnectionError
        }) do
          Lock.stub(:with_lock, true) do
            assert_raises(Errors::ConnectionError) do
              result = @service.run
            end

            assert_equal 2, @logs.length

            parsed_first_log = JSON.parse(@logs.first)
            assert_equal 'miss', parsed_first_log['status']
          end
        end
      end
    end
  end

  # NOTE: Service won't be able to refresh ALL rates for the next 5 minutes
  # even though no rate has been cached.
  # However, expected non-empty values when received success response.
  def test_cache_miss_empty_rates_response
    cache_read_calls = 0
    original_cache_read = Rails.cache.method(:read)

    Rails.logger.stub(:error, ->(msg) { @logs << msg }) do
      Rails.logger.stub(:info, ->(msg) { @logs << msg }) do
        RateApiClient.stub(:get_all_rates, nil) do
          Lock.stub(:with_lock, true) do
            Rails.cache.stub(:read, lambda { |key, *args|
              cache_read_calls += 1 if key == @room_cache_key
              original_cache_read.call(key, *args)
            }) do
              assert_raises(Errors::NotFoundError) do
                result = @service.run
              end

              assert_equal 2, @logs.length

              parsed_first_log = JSON.parse(@logs.first)
              assert_equal 'miss', parsed_first_log['status']

              # Room rate cache read twice:
              # - For initial check
              # - For trying to retrieve recently updated cache
              assert_equal 2, cache_read_calls

              assert_equal 1, Rails.cache.read(Api::V1::PricingService::RATE_STATUS_KEY)
              assert_nil Rails.cache.read('FloatingPointResort:Summer:SingletonRoom:rate')
              assert_nil Rails.cache.read('FloatingPointResort:Summer:BooleanTwin:rate')
              assert_nil Rails.cache.read('RecursionRetreat:Summer:SingletonRoom:rate')
              assert_nil Rails.cache.read('FloatingPointResort:Autumn:SingletonRoom:rate')
            end
          end
        end
      end
    end

    Rails.cache.clear
  end

  # NOTE: Service won't be able to refresh this room rate for the next 5 minutes
  # even though rate has not been cached.
  def test_cache_miss_not_found_in_response
    cache_read_calls = 0
    original_cache_read = Rails.cache.method(:read)

    # Only returns other room(s).
    @all_rates = {
      rates: [
        {
          period: 'Autumn',
          hotel: 'FloatingPointResort',
          room: 'SingletonRoom',
          rate: 2_000
        }
      ]
    }.with_indifferent_access

    Rails.logger.stub(:error, ->(msg) { @logs << msg }) do
      Rails.logger.stub(:info, ->(msg) { @logs << msg }) do
        RateApiClient.stub(:get_all_rates, @all_rates) do
          Lock.stub(:with_lock, true) do
            Rails.cache.stub(:read, lambda { |key, *args|
              cache_read_calls += 1 if key == @room_cache_key
              original_cache_read.call(key, *args)
            }) do
              assert_raises(Errors::NotFoundError) do
                result = @service.run
              end

              assert_equal 2, @logs.length

              parsed_first_log = JSON.parse(@logs.first)
              assert_equal 'miss', parsed_first_log['status']

              # Room rate cache read twice:
              # - For initial check
              # - For trying to retrieve recently updated cache
              assert_equal 2, cache_read_calls

              assert_equal 1, Rails.cache.read(Api::V1::PricingService::RATE_STATUS_KEY)
              assert_nil Rails.cache.read('FloatingPointResort:Summer:SingletonRoom:rate')
              assert_equal 2_000, Rails.cache.read('FloatingPointResort:Autumn:SingletonRoom:rate')
            end
          end
        end
      end
    end

    Rails.cache.clear
  end

  # NOTE: Service won't be able to refresh this room rate for the next 5 minutes
  # even though rate has not been cached.
  def test_cache_miss_invalid_rate
    invalid_rates = [nil, '', 0]

    invalid_rates.each do |rate|
      cache_read_calls = 0
      original_cache_read = Rails.cache.method(:read)

      @all_rates = {
        rates: [
          {
            period: 'Summer',
            hotel: 'FloatingPointResort',
            room: 'SingletonRoom',
            rate: rate
          }
        ]
      }.with_indifferent_access

      @logs = []

      Rails.logger.stub(:error, ->(msg) { @logs << msg }) do
        Rails.logger.stub(:info, ->(msg) { @logs << msg }) do
          RateApiClient.stub(:get_all_rates, @all_rates) do
            Lock.stub(:with_lock, true) do
              Rails.cache.stub(:read, lambda { |key, *args|
                cache_read_calls += 1 if key == @room_cache_key
                original_cache_read.call(key, *args)
              }) do
                assert_raises(Errors::NotFoundError) do
                  result = @service.run
                end

                assert_equal 2, @logs.length

                parsed_first_log = JSON.parse(@logs.first)
                assert_equal 'miss', parsed_first_log['status']

                # Room rate cache read twice:
                # - For initial check
                # - For trying to retrieve recently updated cache
                assert_equal 2, cache_read_calls

                assert_equal 1, Rails.cache.read(Api::V1::PricingService::RATE_STATUS_KEY)
                assert_nil Rails.cache.read('FloatingPointResort:Summer:SingletonRoom:rate')
              end
            end
          end
        end
      end

      Rails.cache.clear
    end
  end
end
