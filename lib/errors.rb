module Errors
  class DynamicPricingError < StandardError
    attr_reader :error_code

    def initialize(message = "Internal Server Error", error_code: :internal_server_error)
      super(message)
      @error_code = error_code
    end
  end

  class ConnectionError < DynamicPricingError
    def initialize(message = "Connection Error")
      super(
        message,
        error_code: :internal_server_error
      )
    end
  end

  class LockTimeoutError < DynamicPricingError
    def initialize(message = "Lock Timeout Error")
      super(
        message,
        error_code: :internal_server_error
      )
    end
  end

  class NotFoundError < DynamicPricingError
    def initialize(message = "Not Found Error")
      super(
        message,
        error_code: :not_found
      )
    end
  end
end
