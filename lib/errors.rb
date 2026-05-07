module Errors
  class DynamicPricingError < StandardError
    attr_reader :error_code

    def initialize(message = nil, error_code: nil)
      super(message)
      @error_code = error_code
    end
  end

  class ConnectionError < DynamicPricingError
    def initialize(message = "Connection Error")
      super(
        message,
        error_code: 500
      )
    end
  end

  class LockTimeoutError < DynamicPricingError
    def initialize(message = "Lock Timeout Error")
      super(
        message,
        error_code: 500
      )
    end
  end
end
