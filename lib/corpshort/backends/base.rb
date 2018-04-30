module Corpshort
  module Backends
    class Base
      class ConflictError < StandardError; end

      def initialize()
      end

      def put_link(link, create_only: false)
        raise NotImplementedError
      end

      def get_link(name)
        raise NotImplementedError
      end

      def delete_link(link_or_name)
        raise NotImplementedError
      end

      def rename_link(link, new_name)
        raise NotImplementedError
      end

      def list_links_by_url(url)
        raise NotImplementedError
      end

      def list_links(token: nil, limit: 30)
        raise NotImplementedError
      end
    end
  end
end
