require "forwardable"

module Retro
  class Model
    extend Forwardable

    def_delegators :"self.class", :api_params, :db

    RETURN_OPTIONS = {
      none: "NONE", all_old: "ALL_OLD", updated_old: "UPDATED_OLD", all_new: "ALL_NEW", updated_new: "UPDATED_NEW"
    }.freeze
    ATTR_TRANSFORMATIONS = { add: "ADD", put: "PUT", delete: "DELETE" }.freeze

    ROOT_PID = "-".freeze
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
      db.delete_item(api_params.merge(key: identifier_params, return_values: RETURN_OPTIONS[:all_old])).attributes
    end

    def put
      push_attributes = item_attributes
      db.put_item(api_params.merge(item: push_attributes, return_values: RETURN_OPTIONS[:all_old]))
      @attributes = push_attributes
    end
    alias :save :put

    def update(method: ATTR_TRANSFORMATIONS[:put], **updates)
      attribute_updates = prepare_attributes(updates).transform_values do |value|
        { value: value, action: method }
      end

      response = db.update_item(api_params.merge(
        key: identifier_params,
        attribute_updates: attribute_updates,
        return_values: RETURN_OPTIONS[:all_new])
      )
      @attributes = response.attributes
    end

    def identifier_params
      { CID => identifier }.tap do |attrs|
        attrs[PID] ||= parent&.identifier || ROOT_PID
        attrs[CID] ||= generate_id
      end
    end

    def to_json
      attributes.to_json
    end

    def assign(attrs)
      attributes.merge!(prepare_attributes(attrs))
      self
    end

    private

    def prepare_attributes(attrs)
      attrs.transform_keys!(&:to_sym)
      attrs.delete(CID)
      attrs.delete(PID)
      attrs
    end

    def generate_id
      SecureRandom.uuid
    end

    def item_attributes
      attributes.dup.tap do |attrs|
        attrs.merge! identifier_params
        attrs["type"] ||= self.class.name.split("::").last.downcase
      end
    end

    class << self
      def api_params
        { table_name: dynamo_table_name }
      end

      def dynamo_table_name
        @table_name
      end

      def find(cid:, pid: ROOT_PID)
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
