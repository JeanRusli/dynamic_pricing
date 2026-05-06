require 'test_helper'

class BaseApiClientTest < ActiveSupport::TestCase
  def setup
    @method = :post
    @path = '/test'

    @request_body = {
      attributes: [
        {
          period: 'Summer',
          hotel: 'FloatingPointResort',
          room: 'SingletonRoom'
        }
      ]
    }.to_json

    @options = { body: @request_body, retries: 1 }

    @code = 200

    @response_body = {
      rates: [
        {
          period: 'Summer',
          hotel: 'FloatingPointResort',
          room: 'SingletonRoom',
          rate: 1000
        }
      ]
    }.to_json

    @response = Struct.new(:code, :body).new(@code, @response_body)

    @logs = []
  end

  # Response: 2xx
  def test_returns_response_and_logs_request_for_2xx
    BaseApiClient.stub(@method, @response) do
      Rails.logger.stub(:info, ->(msg) { @logs << msg }) do
        result = BaseApiClient.request(@method, @path, @options)

        assert_equal @response, result
        assert_equal 2, @logs.length
      end
    end
  end

  # Response: 4xx
  def test_returns_response_and_logs_request_for_4xx
    @code = 400
    @response_body = {
      message: 'Failed to process rates due to an intermittent issue.',
      status: 'error'
    }.to_json
    @response = Struct.new(:code, :body).new(@code, @response_body)

    BaseApiClient.stub(@method, @response) do
      Rails.logger.stub(:info, ->(msg) { @logs << msg }) do
        Rails.logger.stub(:warn, ->(msg) { @logs << msg }) do
          result = BaseApiClient.request(@method, @path, @options)

          assert_equal @response, result
          assert_equal 2, @logs.length
        end
      end
    end
  end

  # Response: 5xx
  def test_retries_and_logs_request_for_5xx
    call_count = 0
    error_response = Struct.new(:code, :body).new(500, 'err')

    BaseApiClient.stub(@method, ->(*) {
      res = (call_count == 0 ? error_response : @response)
      call_count += 1
      res
    }) do
      Rails.logger.stub(:info, ->(msg) { @logs << msg }) do
        Rails.logger.stub(:error, ->(msg) { @logs << msg }) do
          result = BaseApiClient.request(@method, @path, @options)

          assert_equal @response, result
          assert_equal 2, call_count
          assert_equal 4, @logs.length
        end
      end
    end
  end

  def test_no_retry_for_5xx
    @options = { body: @request_body }

    call_count = 0
    error_response = Struct.new(:code, :body).new(500, 'err')

    BaseApiClient.stub(@method, ->(*) {
      call_count += 1
      error_response
    }) do
      Rails.logger.stub(:info, ->(msg) { @logs << msg }) do
        Rails.logger.stub(:error, ->(msg) { @logs << msg }) do
          assert_raises(Errors::ConnectionError) do
            BaseApiClient.request(@method, @path, @options)
          end

          assert_equal 1, call_count
          assert_equal 2, @logs.length
        end
      end
    end
  end

  def test_stop_retry_after_max_retry_for_5xx
    @options = { body: @request_body, retries: 5 }

    call_count = 0
    error_response = Struct.new(:code, :body).new(500, 'err')

    BaseApiClient.stub(@method, ->(*) {
      call_count += 1
      error_response
    }) do
      Rails.logger.stub(:info, ->(msg) { @logs << msg }) do
        Rails.logger.stub(:error, ->(msg) { @logs << msg }) do
          assert_raises(Errors::ConnectionError) do
            BaseApiClient.request(@method, @path, @options)
          end

          assert_equal 3, call_count
          assert_equal 6, @logs.length
        end
      end
    end
  end

  # Timeout Error
  def test_handles_exception
    call_count = 0

    BaseApiClient.stub(@method, ->(*) {
      call_count += 1
      raise Net::ReadTimeout
    }) do
      Rails.logger.stub(:info, ->(msg) { @logs << msg }) do
        Rails.logger.stub(:error, ->(msg) { @logs << msg }) do
          assert_raises(Net::ReadTimeout) do
            BaseApiClient.request(@method, @path, @options)
          end

          assert_equal 2, call_count
          assert_equal 4, @logs.length
        end
      end
    end
  end
end
