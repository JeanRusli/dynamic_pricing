class ApplicationController < ActionController::API
  around_action :monitor_request

  private

  def default_log_data
    {
      tags: ['dynamic_pricing', 'incoming_request', controller_name],
      method: request.method,
      path: request.path,
      status: response.status
    }
  end

  # TODO: Using logger for now, need to replace with actual monitoring tool.
  def send_metric(duration_ms)
    Rails.logger.info({
      metric: 'incoming_request',
      service: 'dynamic_pricing',
      controller: controller_name,
      method: request.method,
      path: request.path,
      status: response.status,
      duration_ms:
    }.to_json)
  end

  def monitor_request
    start_time = Time.now

    begin
      yield
    rescue Errors::DynamicPricingError => e
      @rescued_error = e
      msg = (e.error_code == :internal_server_error ? 'Internal Server Error' : e.message )
      render json: { error: msg }, status: e.error_code
    rescue StandardError => e
      @rescued_error = e
      render json: { error: 'Internal Server Error' }, status: :internal_server_error
    ensure
      duration_ms = ((Time.now - start_time) * 1000).round(2)

      log_data = default_log_data.merge({
        timestamp: start_time.iso8601,
        duration_ms:
      })

      if response.status < 400
        Rails.logger.info(log_data.merge({
          level: 'info',
          message: 'ok',
        }).to_json)
      else
        Rails.logger.error(log_data.merge({
          level: 'error',
          message: @rescued_error&.message || response.body
        }).to_json)
      end

      send_metric(duration_ms)
    end
  end
end
