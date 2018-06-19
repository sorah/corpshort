require 'aws-sdk-dynamodb'
require 'date'
require 'time'
require 'corpshort/backends/base'
require 'corpshort/link'

module Corpshort
  module Backends
    class Dynamodb < Base
      def initialize(table:, region:)
        @table_name = table
        @region = region
      end

      def table
        @table ||= dynamodb.table(@table_name)
      end

      def dynamodb
        @dynamodb ||= Aws::DynamoDB::Resource.new(region: @region)
      end

      def put_link(link, create_only: false)
        table.update_item(
          key: {
            'name' => link.name,
          },
          update_expression: 'SET #u = :url, updated_at_partition = :ts_partition, updated_at = :updated_at',
          condition_expression: create_only ? 'attribute_not_exists(#n)' : nil,
          expression_attribute_names: create_only ? {'#u' => 'url', '#n' => 'name'} : {'#u' => 'url'},
          expression_attribute_values: {
            ':url' => link.url,
            ':ts_partition' => ts_partition(link.updated_at),
            ':updated_at' => link.updated_at.iso8601,
          },
        )
      rescue Aws::DynamoDB::Errors::ConditionalCheckFailedException
        raise ConflictError
      end

      def get_link(name)
        item = table.query(
          limit: 1,
          select: 'ALL_ATTRIBUTES',
          key_condition_expression: '#n = :name',
          expression_attribute_names: {'#n' => 'name'},
          expression_attribute_values: {":name" => name},
        ).items.first

        if item && !item.empty?
          Link.new(item, backend: self)
        else
          nil
        end
      end

      def delete_link(link)
        name = link.is_a?(String) ? link : link.name
        table.delete_item(
          key: {
            'name' => name,
          },
        )
      end

      def list_links_by_url(url)
        table.query(
          index_name: 'url-updated_at-index',
          select: 'ALL_PROJECTED_ATTRIBUTES',
          key_condition_expression: '#u = :url',
          expression_attribute_names: {"#u" => 'url'},
          expression_attribute_values: {":url" => url},
        ).items.map { |_| _['name'] }
      end

      def list_links(token: nil, limit: 30)
        partition, last_key = parse_token(token)
        limit.times do
          result = table.query(
            index_name: 'updated_at_partition-updated_at-index',
            select: 'ALL_PROJECTED_ATTRIBUTES',
            scan_index_forward: false,
            exclusive_start_key: last_key ? last_key : nil,
            key_condition_expression: 'updated_at_partition = :partition',
            expression_attribute_values: {":partition" => partition.strftime('%Y-%m')},
            limit: 1 || limit,
          )

          unless result.items.empty?
            return [result.items.map{ |_| _['name'] }, result.last_evaluated_key&.values_at('updated_at_partition', 'name', 'updated_at')&.join(?:)]
          end

          partition = partition.to_date.prev_month
          last_key = nil
          sleep 0.05
        end
      end

      private

      def parse_token(token)
        if token.nil?
          return [Time.now, nil]
        end
        partition, name, ts = token.split(?:,3)
        [Time.strptime(partition, '%Y-%m'), ts ? {"updated_at_partition" => partition, "updated_at" => ts, "name" => name} : nil]
      end

      def ts_partition(time)
        time.strftime('%Y-%m')
      end
    end
  end
end
