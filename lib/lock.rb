class Lock
  class << self
    PREFIX = "dynamic_pricing:lock".freeze
    DEFAULT_WAIT_TIME = 0.5.freeze
    DEFAULT_TIMEOUT = 6.freeze

    def with_lock(lock_name, lock_ttl, wait_time: DEFAULT_WAIT_TIME, timeout: DEFAULT_TIMEOUT)
      start = Time.now
      key = "#{PREFIX}:#{lock_name}"
      lock_val = SecureRandom.uuid

      loop do
        acquired = acquire_lock(key, lock_val, lock_ttl)

        if acquired
          begin
            return yield
          ensure
            release_lock(key, lock_val)
          end
        end

        if Time.now - start > timeout
          raise Errors::LockTimeoutError.new("Lock Timeout: Could not acquire lock for #{lock_name}")
        end

        sleep(wait_time + rand * 0.1)
      end
    end

    private

    def acquire_lock(key, val, ttl)
      APP_REDIS.set(key, val, nx: true, ex: ttl)
    end

    def release_lock(key, val)
      APP_REDIS.del(key) if APP_REDIS.get(key) == val
    end
  end
end
