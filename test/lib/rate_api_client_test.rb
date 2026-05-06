require 'test_helper'

class RateApiClientTest < ActiveSupport::TestCase
  def setup
    @code = 200

    @expected_result = {
      rates: [
        {
          period: 'Summer',
          hotel: 'FloatingPointResort',
          room: 'SingletonRoom',
          rate: 1000
        }
      ]
    }.deep_stringify_keys
    @response_body = @expected_result.to_json

    @response = Struct.new(:code, :body).new(@code, @response_body)

    @payload = {}
    @logs = []
  end

  def test_get_all_rates_success_response_all_hotels
    BaseApiClient.stub(:request, ->(*args) {
      @payload = args.last[:body]
      @response
    }) do
      result = RateApiClient.get_all_rates

      assert_equal @expected_result, result

      parsed_payload = JSON.parse(@payload)
      assert_equal 36, parsed_payload['attributes'].length
    end
  end

  def test_get_all_rates_success_response_one_hotel
    BaseApiClient.stub(:request, ->(*args) {
      @payload = args.last[:body]
      @response
    }) do
      result = RateApiClient.get_all_rates(hotels: ['FloatingPointResort'])

      assert_equal @expected_result, result

      parsed_payload = JSON.parse(@payload)
      assert_equal 12, parsed_payload['attributes'].length
      assert_equal 'FloatingPointResort', parsed_payload['attributes'].first['hotel']
    end
  end

  def test_get_all_rates_nil_hotel_given
    BaseApiClient.stub(:request, ->(*args) {
      @payload = args.last[:body]
      @response
    }) do
      result = RateApiClient.get_all_rates(hotels: nil)

      assert_equal @expected_result, result

      parsed_payload = JSON.parse(@payload)
      assert_equal 36, parsed_payload['attributes'].length
    end
  end

  def test_get_all_rates_success_response_with_error_message
    @code = 200
    @response_body = {
      message: 'Failed to process rates due to an intermittent issue.',
      status: 'error'
    }.to_json
    @response = Struct.new(:code, :body).new(@code, @response_body)

    BaseApiClient.stub(:request, @response) do
      Rails.logger.stub(:warn, ->(msg) { @logs << msg }) do
        assert_raises(Errors::ConnectionError) do
          RateApiClient.get_all_rates
        end

        assert_equal 1, @logs.length
      end
    end
  end

  def test_get_all_rates_error_response
    @code = 400
    @response_body = {
      error: "Invalid attribute: {'hotel': 'FloatingPointResort', 'room': 'SingletonRoom'}"
    }.to_json
    @response = Struct.new(:code, :body).new(@code, @response_body)

    BaseApiClient.stub(:request, @response) do
      assert_raises(Errors::ConnectionError) do
        RateApiClient.get_all_rates
      end
    end
  end

  def test_get_all_rates_exception_raised
    BaseApiClient.stub(:request, ->(*) {
      raise Net::ReadTimeout
    }) do
      assert_raises(Net::ReadTimeout) do
        RateApiClient.get_all_rates
      end
    end
  end
end
