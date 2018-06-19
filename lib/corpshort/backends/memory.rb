require 'thread'
require 'corpshort/backends/base'
require 'corpshort/link'

module Corpshort
  module Backends
    class Memory < Base
      def initialize()
        @lock = Mutex.new
        @links = {}
        @links_by_url = {}
      end

      attr_reader :links, :links_by_url

      def put_link(link, create_only: false)
        @lock.synchronize do
          old_link = @links[link.name]
          if create_only && old_link
            raise ConflictError
          end
          old_url = old_link&.fetch(:url, nil)
          if old_link && link.url != old_url
            @links_by_url[old_url].delete(link.name)
          end
          @links[link.name] = link.to_h
          (@links_by_url[link.url] ||= {})[link.name] = true
        end
        nil
      end

      def get_link(name)
        data = @links[name]
        if data && !data.empty?
          Link.new(data, backend: self)
        else
          nil
        end
      end

      def delete_link(link)
        @lock.synchronize do
          name = link.is_a?(String) ? link : link.name
          data = @links[name]
          if @links[name]
            @links.delete name
            @links_by_url[data[:url]].delete name
          end
        end
      end

      def list_links_by_url(url)
        @links_by_url[url].keys
      end

      def list_links(token: nil, limit: 30)
        [@links.keys, nil]
      end
    end
  end
end
