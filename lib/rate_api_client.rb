class RateApiClient < BaseApiClient
  base_uri ENV.fetch('RATE_API_URL', 'http://localhost:8080')
  headers "Content-Type" => "application/json"
  headers 'token' => ENV.fetch('RATE_API_TOKEN', '04aa6f42aa03f220c2ae9a276cd68c62')

  # Current scope: Small set of room variations which can be defined using constants.
  ALL_HOTELS = %w[FloatingPointResort GitawayHotel RecursionRetreat].freeze
  ALL_PERIODS = %w[Summer Autumn Winter Spring].freeze
  ALL_ROOMS = %w[SingletonRoom BooleanTwin RestfulKing].freeze

  # TODO: Clean up if not used.
  def self.get_rate(period:, hotel:, room:)
    params = {
      attributes: [
        {
          period: period,
          hotel: hotel,
          room: room
        }
      ]
    }.to_json

    response = request(:post, "/pricing", body: params)

    JSON.parse(response.body)
  end

  def self.get_all_rates(hotels: ALL_HOTELS)
    hotels = hotels.presence || ALL_HOTELS
    all_rooms = hotels.product(ALL_PERIODS, ALL_ROOMS).map do |hotel, period, room|
      {
        period: period,
        hotel: hotel,
        room: room
      }
    end
    params = { attributes: all_rooms }.to_json

    response = request(:post, "/pricing", body: params, retries: 1)

    if response.code.to_i >= 400
      raise Errors::ConnectionError
    end

    parsed_response = JSON.parse(response.body).with_indifferent_access

    if parsed_response&.dig('status') == 'error'
      Rails.logger.warn({
        level: 'warn',
        tags: ['dynamic_pricing', 'api_client', self.name.underscore],
        method: 'post',
        path: '/pricing',
        response_code: response.code.to_i,
        response_body: response.body,
      }.to_json)
      raise Errors::ConnectionError
    end

    parsed_response
  end
end
