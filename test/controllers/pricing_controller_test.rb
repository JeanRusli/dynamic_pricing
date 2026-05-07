require "test_helper"

class Api::V1::PricingControllerTest < ActionDispatch::IntegrationTest
  def setup
    @period = "Summer"
    @hotel = "FloatingPointResort"
    @room = "SingletonRoom"

    @info_logs = []
    @error_logs = []
  end

  test "should get pricing with all parameters" do
    mock_service = Minitest::Mock.new
    mock_service.expect(:run, "15000")
    mock_service.expect(:result, "15000")

    logger_mock = Minitest::Mock.new
    3.times do # 1 default log from Rails, 1 log, 1 metric
      logger_mock.expect(:info, nil) { |data| @info_logs << data }
    end

    Rails.stub(:logger, logger_mock) do
      Api::V1::PricingService.stub(:new, ->(period:, hotel:, room:) {
        assert_equal @period, period
        assert_equal @hotel, hotel
        assert_equal @room, room

        mock_service
      }) do
        get api_v1_pricing_url, params: {
          period: @period,
          hotel: @hotel,
          room: @room
        }

        assert_response :success
        assert_equal "application/json", @response.media_type

        json_response = JSON.parse(@response.body)
        assert_equal "15000", json_response["rate"]
      end
    end

    mock_service.verify
  end

  test "should return actual error when DynamicPricingError (404) is raised" do
    mock_service = Minitest::Mock.new
    def mock_service.run
      raise Errors::NotFoundError.new("Rate not found.")
    end

    logger_mock = Minitest::Mock.new
    2.times do # 1 default log from Rails, 1 metric
      logger_mock.expect(:info, nil) { |data| @info_logs << data }
    end
    logger_mock.expect(:error, nil) { |data| @error_logs << data }

    Rails.stub(:logger, logger_mock) do
      Api::V1::PricingService.stub(:new, ->(period:, hotel:, room:) {
        assert_equal @period, period
        assert_equal @hotel, hotel
        assert_equal @room, room

        mock_service
      }) do
        get api_v1_pricing_url, params: {
          period: @period,
          hotel: @hotel,
          room: @room
        }

        assert_response :not_found
        assert_equal "application/json", @response.media_type

        json_response = JSON.parse(@response.body)
        assert_equal json_response["error"], "Rate not found."
      end
    end
  end

  test "should return standardized error when DynamicPricingError (500) is raised" do
    mock_service = Minitest::Mock.new
    def mock_service.run
      raise Errors::LockTimeoutError
    end

    logger_mock = Minitest::Mock.new
    2.times do # 1 default log from Rails, 1 metric
      logger_mock.expect(:info, nil) { |data| @info_logs << data }
    end
    logger_mock.expect(:error, nil) { |data| @error_logs << data }

    Rails.stub(:logger, logger_mock) do
      Api::V1::PricingService.stub(:new, ->(period:, hotel:, room:) {
        assert_equal @period, period
        assert_equal @hotel, hotel
        assert_equal @room, room

        mock_service
      }) do
        get api_v1_pricing_url, params: {
          period: @period,
          hotel: @hotel,
          room: @room
        }

        assert_response :internal_server_error
        assert_equal "application/json", @response.media_type

        json_response = JSON.parse(@response.body)
        assert_equal json_response["error"], "Internal Server Error"
      end
    end
  end

  test "should return standardized error when StandardError is raised" do
    mock_service = Minitest::Mock.new
    def mock_service.run
      raise StandardError, "some error"
    end

    logger_mock = Minitest::Mock.new
    2.times do # 1 default log from Rails, 1 metric
      logger_mock.expect(:info, nil) { |data| @info_logs << data }
    end
    logger_mock.expect(:error, nil) { |data| @error_logs << data }

    Rails.stub(:logger, logger_mock) do
      Api::V1::PricingService.stub(:new, ->(period:, hotel:, room:) {
        assert_equal @period, period
        assert_equal @hotel, hotel
        assert_equal @room, room

        mock_service
      }) do
        get api_v1_pricing_url, params: {
          period: @period,
          hotel: @hotel,
          room: @room
        }

        assert_response :internal_server_error
        assert_equal "application/json", @response.media_type

        json_response = JSON.parse(@response.body)
        assert_equal json_response["error"], "Internal Server Error"
      end
    end
  end

  test "should return error without any parameters" do
    get api_v1_pricing_url

    assert_response :bad_request
    assert_equal "application/json", @response.media_type

    json_response = JSON.parse(@response.body)
    assert_includes json_response["error"], "Missing required parameters"
  end

  test "should handle empty parameters" do
    get api_v1_pricing_url, params: {
      period: "",
      hotel: "",
      room: ""
    }

    assert_response :bad_request
    assert_equal "application/json", @response.media_type

    json_response = JSON.parse(@response.body)
    assert_includes json_response["error"], "Missing required parameters"
  end

  test "should reject invalid period" do
    get api_v1_pricing_url, params: {
      period: "summer-2024",
      hotel: "FloatingPointResort",
      room: "SingletonRoom"
    }

    assert_response :unprocessable_content
    assert_equal "application/json", @response.media_type

    json_response = JSON.parse(@response.body)
    assert_includes json_response["error"], "Invalid period"
  end

  test "should reject invalid hotel" do
    get api_v1_pricing_url, params: {
      period: "Summer",
      hotel: "InvalidHotel",
      room: "SingletonRoom"
    }

    assert_response :unprocessable_content
    assert_equal "application/json", @response.media_type

    json_response = JSON.parse(@response.body)
    assert_includes json_response["error"], "Invalid hotel"
  end

  test "should reject invalid room" do
    get api_v1_pricing_url, params: {
      period: "Summer",
      hotel: "FloatingPointResort",
      room: "InvalidRoom"
    }

    assert_response :unprocessable_content
    assert_equal "application/json", @response.media_type

    json_response = JSON.parse(@response.body)
    assert_includes json_response["error"], "Invalid room"
  end
end
