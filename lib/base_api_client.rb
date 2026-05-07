class BaseApiClient
  include HTTParty

  # TODO: Move this to ENV.
  DEFAULT_TIMEOUT = 2 # seconds
  DEFAULT_RETRY = 0
  MAX_RETRY = 2

  RETRYABLE_ERRORS = [
    Net::OpenTimeout,
    Net::ReadTimeout,
    Errno::ECONNREFUSED,
    Errors::ConnectionError
  ]

  def self.request(method, path, options = {})
    final_options = default_options.merge(options)
    ctx = build_request_context(method, path, final_options)

    attempt_count = 0
    begin
      attempt_count += 1
      ctx[:start_time] = Time.now
      response = send(method, path, final_options)
      ctx[:duration] = Time.now - ctx[:start_time]

      ctx[:response_code] = response.code.to_i

      case ctx[:response_code]
      when 400..499
        ctx[:response_body] = response.body
        log_warn(ctx)
      when 500..599
        raise Errors::ConnectionError
      else
        log_info(ctx)
      end

      send_metrics(ctx)

      return response
    rescue *RETRYABLE_ERRORS => e
      log_error(ctx, e)
      send_metrics(ctx)

      if allowed_to_retry?(ctx, attempt_count)
        retry
      else
        raise
      end
    end
  end

  private

  def self.build_request_context(method, path, options = {})
    {
      method: method,
      path: path,
      options: options,
      class_name: self.name.underscore,
      track_id: options.delete(:track_id),
      start_time: nil,
      duration: nil,
      response_code: nil,
      response_body: nil
    }
  end

  def self.default_options
    {
      timeout: DEFAULT_TIMEOUT,
      retries: DEFAULT_RETRY
    }
  end

  def self.allowed_to_retry?(ctx, attempt_count)
    attempt_count <= ctx[:options][:retries].to_i && attempt_count <= MAX_RETRY
  end

  # Logging

  def self.default_log_data(ctx)
    {
      tags: ['dynamic_pricing', 'api_client', ctx[:class_name]],
      method: ctx[:method],
      path: ctx[:path],
      response_code: ctx[:response_code],
      track_id: ctx[:track_id],
      request_id: Thread.current[:request_id]
    }
  end

  def self.log_info(ctx)
    log_data = default_log_data(ctx).merge({
      level: 'info',
      duration_ms: (ctx[:duration] * 1000).round(2)
    }).compact

    Rails.logger.info(log_data.to_json)
  rescue
    nil
  end

  def self.log_warn(ctx)
    log_data = default_log_data(ctx).merge({
      level: 'warn',
      duration_ms: (ctx[:duration] * 1000).round(2),
      response_body: ctx[:response_body]
    }).compact

    Rails.logger.warn(log_data.to_json)
  rescue
    nil
  end

  def self.log_error(ctx, err)
    log_data = default_log_data(ctx).merge({
      level: 'error',
      error: err.class.name,
      message: err.message,
      backtrace: err.backtrace&.take(5)&.join("\n")
    }).compact

    Rails.logger.error(log_data.to_json)
  rescue
    nil
  end

  # Metrics
  # TODO: Using logger for now, need to replace with actual monitoring tool.

  def self.send_metrics(ctx)
    status = ctx[:response_code].to_i >= 200 && ctx[:response_code].to_i < 400 ? 'success' : 'fail'

    Rails.logger.info({
      metric: 'api_call',
      service: 'dynamic_pricing',
      class: ctx[:class_name],
      method: ctx[:method],
      path: ctx[:path],
      status: status,
      duration_ms: (ctx[:duration].to_f * 1000).round(2),
      response_code: ctx[:response_code]
    }.to_json)
  rescue
    nil
  end
end
