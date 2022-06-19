require "forwardable"

module Retro
  class Model
    extend Forwardable

    def_delegators :"self.class", :api_params, :db

    RETURN_OPTIONS = {
      none: "NONE", all_old: "ALL_OLD", updated_old: "UPDATED_OLD", all_new: "ALL_NEW", updated_new: "UPDATED_NEW"
    }.freeze

    PID = "pid".freeze
    CID = "cid".freeze

    attr_reader :attributes
    attr_accessor :parent

    def initialize(attributes = {})
      @attributes = attributes
    end

    def identifier
      attributes[CID]
    end

    def new?
      identifier.nil?
    end

    def destroy
      db.delete_item(api_params.merge(identifier_params))
    end

    def put
      response = db.put_item(api_params.merge(item_params).merge(return_values: RETURN_OPTIONS[:all_old]))
    end
    alias :save :put

    def identifier_params
      { CID => identifier }.tap do |attrs|
        attrs[PID] = parent.identifier if parent
        attrs[CID] ||= generate_id
      end
    end

    def to_json
      attributes.to_json
    end

    private

    def generate_id
      SecureRandom.uuid
    end

    def item_attributes
      attributes.dup.tap do |attrs|
        attrs.merge! identifier_params
        attrs["type"] ||= self.class.name.split("::").last.downcase
      end
    end

    def item_params
      { item: item_attributes }
    end

    class << self
      def api_params
        { table_name: dynamo_table_name }
      end

      def dynamo_table_name
        @table_name
      end

      def find(cid:, pid: nil)
        db.get_item(**api_params, key: { pid: pid, cid: cid }).item.yield_self { |item| new(item) if item }
      end

      def all
        db.scan(api_params).items.map { |attrs| new(attrs) }
      end

      def db
        @db ||= ::Aws::DynamoDB::Client.new
      end

      def table_name(name)
        @table_name = "retro-#{name}"
      end
    end
  end
end
