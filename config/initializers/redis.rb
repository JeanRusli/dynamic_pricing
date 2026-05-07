# frozen_string_literal: true

require 'redis'

APP_REDIS =
  if Rails.env.test?
    MockRedis.new
  else
    Redis.new(url: ENV.fetch('REDIS_URL'))
  end
