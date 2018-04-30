require 'bundler/setup'
require 'securerandom'

require 'corpshort'

if ENV['RACK_ENV'] == 'production'
  raise 'Set $SECRET_KEY_BASE' unless ENV['SECRET_KEY_BASE']
end

config = {
}

case ENV.fetch('CORPSHORT_BACKEND', 'redis')
when 'redis'
  config[:backend] = Corpshort::Backends::Redis.new(
    redis: ENV.key?('REDIS_URL') ? lambda { Redis.new(url: ENV['REDIS_URL']) } : Redis.method(:current),
    prefix: ENV.fetch('CORPSHORT_REDIS_PREFIX', 'corpshort:'),
  )
else
  raise ArgumentError, "Unsupported $CORPSHORT_BACKEND"
end

use(
  Rack::Session::Cookie,
  key: 'corpshortsess',
  expire_after: 86400,
  secure: ENV.fetch('CORPSHORT_SECURE_SESSION', ENV['RACK_ENV'] == 'production' ? '1' : nil) == '1',
  secret: ENV.fetch('SECRET_KEY_BASE', SecureRandom.base64(256)),
)

run Corpshort.app(config)
