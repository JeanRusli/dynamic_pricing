require 'test_helper'
require 'mock_redis'

class LockTest < ActiveSupport::TestCase
  def setup
    @redis = APP_REDIS
    @lock = 'test-lock'
    @key = 'dynamic_pricing:lock:test-lock'
    @result = nil
  end

  def test_with_lock_executes_block_and_releases_lock
    # Remove stuck cache (if any)
    @redis.del(@key)

    Lock.with_lock(@lock, 10) do
      assert_equal true, @redis.get(@key).present?
      assert_nil @result

      @result = 'executed'
    end

    assert_equal 'executed', @result
    assert_nil @redis.get(@key)
  end

  def test_with_lock_releases_lock_when_block_crashes
    # Remove stuck cache (if any)
    @redis.del(@key)

    assert_raises(RuntimeError) do
      Lock.with_lock(@lock, 10) do
        assert_equal true, @redis.get(@key).present?
        raise 'some error'
      end
    end

    assert_nil @redis.get(@key)
  end

  def test_with_lock_executes_block_and_skip_lock_release
    # Remove stuck cache (if any)
    @redis.del(@key)

    redis_del_called = false

    APP_REDIS.stub(:del, ->(*) { redis_del_called = true }) do
      Lock.with_lock(@lock, 0.5) do
        assert_nil @result

        @result = 'executed'

        # To make sure lock already expired.
        sleep 0.5

        @redis.set(@key, 'some value', ex: 2)
      end
    end

    assert_equal false, redis_del_called
    assert_equal 'executed', @result

    assert_equal true, @redis.get(@key).present?
    @redis.del(@key)
  end

  def test_with_lock_acquires_after_waiting
    acquire_calls = 0
    has_slept = false

    original = Lock.method(:acquire_lock)

    @redis.set(@key, 1, ex: 2)

    Lock.stub(:sleep, ->(*) { has_slept = true }) do
      Lock.stub(:acquire_lock, lambda { |*args|
        acquire_calls += 1

        if acquire_calls > 2
          @redis.del(@key)
        end

        original.call(*args)
      }) do
        Lock.with_lock(@lock, 10, timeout: 3) do
          assert_equal true, @redis.get(@key).present?
          assert_nil @result

          @result = 'executed'
        end
      end
    end

    assert_equal 'executed', @result
    assert_nil @redis.get(@key)
    assert_equal 3, acquire_calls
    assert_equal true, has_slept
  end

  def test_with_lock_raises_error_on_timeout
    @redis.set(@key, 1, ex: 1)

    assert_raises(Errors::LockTimeoutError) do
      # Timeout (0.5) less than existing cache TTL (1).
      Lock.with_lock(@lock, 10, timeout: 0.5) do
        @result = 'executed'
      end
    end

    assert_nil @result

    @redis.del(@key)
  end
end
