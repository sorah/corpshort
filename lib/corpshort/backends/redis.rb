require 'digest/sha2'
require 'redis'

require 'corpshort/backends/base'

module Corpshort
  module Backends
    class Redis < Base
      def initialize(redis: ::Redis.method(:current), prefix: "corpshort:")
        @redis = redis
        @prefix = prefix
      end

      attr_reader :prefix

      def put_link(link, create_only: false)
        key = link_key(link)

        redis.watch(key) do 
          old_url = redis.hget(key, 'url')

          if create_only && old_url
            redis.unwatch(key)
            raise ConflictError, "#{link.name} already exists"
          end

          redis.multi do |m|
            m.del(key)
            m.mapped_hmset(key, link.as_json)
            m.zadd(links_key, link.updated_at.to_i, link.name)

            if old_url && link.url != old_url
              m.zrem(url_key(old_url), link.name)
            end
            m.zadd(url_key(link.url), link.updated_at.to_i, link.name)
          end
        end
      end

      def get_link(name)
        data = redis.hgetall(link_key(name))
        if data && !data.empty?
          Link.new(data, backend: self)
        else
          nil
        end
      end

      def delete_link(link)
        key = link_key(link)
        redis.watch(key) do
          url = redis.hget(key, 'url')
          link_url_key = url_key(url)

          redis.multi do |m|
            m.zrem(links_key, link)
            m.zrem(link_url_key, link)
            m.del(key)
          end
        end
      end

      def rename_link(link, new_name)
        link_key = link_key(link)
        new_key = link_key(new_name)

        redis.watch(link_key) do
          url = redis.hget(link_key, 'url')
          link_url_key = url_key(url)

          redis.multi do |m|
            m.renamenx(link_key, new_key)
            m.hset(new_key, 'name', new_name)
            m.zrem(links_key, link.name)
            m.zadd(links_key, link.updated_at.to_i, new_name)
            m.zrem(link_url_key, link.name)
            m.zadd(link_url_key, link.updated_at.to_i, new_name)
          end
        end
      end

      def list_links_by_url(url)
        redis.zrevrangebyscore(url_key(url), '+inf', '-inf')
      end

      def list_links(token: nil, limit: 30)
        names = if token
                  redis.zrevrangebyscore(links_key, "(#{token}", '-inf', limit: [0, limit], with_scores: true)
                else
                  redis.zrevrangebyscore(links_key, '+inf', '-inf', limit: [0, limit], with_scores: true)
                end

        [names.map(&:first), names[-1]&.last]
      end

      def redis
        Thread.current[redis_thread_key] ||= @redis.call
      end

      private

      def url_key(url)
        "#{@prefix}url:#{Digest::SHA384.hexdigest(url)}"
      end

      def links_key
        "#{@prefix}links"
      end

      def link_key(link)
        name = link.is_a?(String) ? link : link.name
        "#{@prefix}link:#{name}"
      end

      def redis_thread_key
        @redis_thread_key ||= :"corpshort_backend_redis_#{self.__id__}"
      end
    end
  end
end
