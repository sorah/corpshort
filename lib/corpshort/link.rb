require 'time'
require 'json'

module Corpshort
  class Link
    class NoBackendError < StandardError; end
    class ValidationError < StandardError; end

    NAME_REGEXP = %r{\A[a-zA-Z0-9./\-_]+\z}

    def self.validate_name(name)
      raise ValidationError, "@name should satisfy #{NAME_REGEXP}" unless name.match?(NAME_REGEXP)
    end

    def initialize(data, backend: nil)
      @backend = backend

      @name = data[:name] || data['name']
      @url = data[:url] || data['url']
      @parsed_url_point = nil
      self.updated_at = data[:updated_at] || data['updated_at']

      validate!
    end

    def validate!
      raise ValidationError, "@name, @url are required" unless name && url
      raise ValidationError, "invalid @url (URL needs scheme and host to be considered valid)" unless parsed_url.scheme && parsed_url.host
      self.class.validate_name(name)
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

    def parsed_url
      @parsed_url = nil if @parsed_url_point != url
      @parsed_url ||= url.yield_self do |u|
        @parsed_url_point = u
        URI.parse(u)
      end
    end

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
      as_json.to_json
    end
  end
end
