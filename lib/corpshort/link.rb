require 'time'
require 'json'

module Corpshort
  class Link
    class NoBackendError < StandardError; end
    class ValidationError < StandardError; end

    def initialize(data, backend: nil)
      @backend = backend

      @name = data[:name] || data['name']
      @url = data[:url] || data['url']
      self.updated_at = data[:updated_at] || data['updated_at']

      validate!
    end

    def validate!
      raise ValidationError, "@name, @url are required" unless name && url
    end

    def save!(backend = nil, create_only: false)
      @backend = backend if backend
      raise NoBackendError unless @backend
      validate!
      self.updated_at = Time.now
      @backend.put_link(self, create_only: create_only)
    end

    attr_reader :backend
    attr_reader :name, :updated_at
    attr_accessor :url

    def updated_at=(ts)
      @updated_at = case ts
      when Time
        ts
      when String
        Time.iso8601(ts)
      when nil
        nil
      else
        raise TypeError, "link.updated_at must be a Time or a String (ISO 8601 formatted)"
      end
    end

    def to_h
      {
        name: name,
        url: url,
        updated_at: updated_at,
      }
    end

    def as_json
      to_h.tap do |h|
        h[:updated_at] = h[:updated_at].iso8601 if h[:updated_at]
      end
    end

    def to_json
      to_h.to_json
    end
  end
end
