# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Evgeny Sokolov (FastJoe)

require 'bigdecimal'

module ActivePostgrest
  class Base
    POSTGRES_TYPE_CAST = {
      'date' => :date,
      'timestamp' => :datetime,
      'timestamp with time zone' => :datetime,
      'timestamp without time zone' => :datetime,
      'time' => :time,
      'time with time zone' => :time,
      'time without time zone' => :time,
      'numeric' => :decimal,
      'decimal' => :decimal,
      'real' => :decimal,
      'double precision' => :decimal
    }.freeze

    def self.table_name
      @table_name ||= name.demodulize.underscore.pluralize
    end

    class << self
      attr_writer :table_name, :schema_name
    end

    def self.schema_name
      @schema_name || (superclass.schema_name if superclass.respond_to?(:schema_name))
    end

    def self.primary_key
      @primary_key ||= 'id'
    end

    def self.primary_key=(key)
      @primary_key = key.to_s
    end

    def self.establish_connection(url: ENV.fetch('POSTGREST_URL'), jwt_token: nil)
      @connection = ActivePostgrest::Client.new(url, jwt_token)
    end

    def self.connection
      @connection ||
        if superclass.respond_to?(:connection)
          superclass.connection
        else
          ActivePostgrest::Client.new
        end
    end

    def self.attribute(name, type)
      @attribute_types ||= {}
      @attribute_types[name.to_s] = type
    end

    def self.attribute_types
      @attribute_types || {}
    end

    def self.schema
      connection.table_schema(table_name)
    end

    def self.attributes
      schema['properties']&.transform_values { _1['format'] } || {}
    end

    def self.belongs_to(name, class_name: nil, foreign_key: nil)
      assoc   = name.to_s
      klass   = class_name&.to_s || assoc.camelize
      table   = klass.underscore.pluralize
      fk      = foreign_key&.to_s
      aliased = fk || (klass.underscore != assoc)
      key     = aliased ? assoc : table

      define_method(assoc) do
        val = @attributes[key]
        return nil if val.nil? || (val.is_a?(Array) && val.empty?)

        klass.constantize.new(val.is_a?(Array) ? val.first : val)
      end

      define_singleton_method(:"with_#{assoc}") do |fields: []|
        if aliased
          joins(table.to_sym, as: assoc.to_sym, foreign_key: fk&.to_sym, select: fields)
        else
          joins(table.to_sym, select: fields)
        end
      end
    end

    def self.has_one(name, class_name: nil)
      assoc = name.to_s
      klass = class_name&.to_s || assoc.camelize

      define_method(assoc) do
        val = @attributes[assoc]
        return nil if val.nil? || (val.is_a?(Array) && val.empty?)

        klass.constantize.new(val.is_a?(Array) ? val.first : val)
      end

      define_singleton_method(:"with_#{assoc}") do |fields: []|
        embed(assoc.to_sym, fields: fields)
      end
    end

    def self.has_many(name, class_name: nil)
      assoc = name.to_s
      klass = class_name&.to_s || assoc.singularize.camelize

      define_method(assoc) do
        val = @attributes[assoc]
        return [] if val.nil?

        Array(val).map { klass.constantize.new(_1) }
      end

      define_singleton_method(:"with_#{assoc}") do |fields: []|
        embed(assoc.to_sym, fields: fields)
      end
    end

    def self.scope(name, body)
      define_singleton_method(name) { |*args, **kwargs| body.call(*args, **kwargs) }
    end

    def self.relation
      rel = ActivePostgrest::Relation.new(table_name, connection, self)
      schema_name ? rel.with_schema(schema_name) : rel
    end

    def self.all                   = relation
    def self.none                  = relation.none
    def self.anonymous             = relation.anonymous
    def self.with_token(jwt)       = relation.with_token(jwt)
    def self.with_schema(name)     = relation.with_schema(name)
    def self.where(filters = nil)  = relation.where(filters)
    def self.not_where(filters)    = relation.not_where(filters)
    def self.or_where(conditions)  = relation.or_where(conditions)
    def self.and_where(conditions) = relation.and_where(conditions)
    def self.order(...)            = relation.order(...)
    def self.reorder(...)          = relation.reorder(...)
    def self.limit(n)              = relation.limit(n)
    def self.offset(n)             = relation.offset(n)
    def self.joins(...)            = relation.joins(...)
    def self.embed(...)            = relation.embed(...)
    def self.select(...)           = relation.select(...)
    def self.spread(...)           = relation.spread(...)

    def self.first(n = nil)       = n ? relation.limit(n).to_a : relation.first
    def self.last(n = nil)        = n ? relation.order(primary_key, :desc).limit(n).to_a.reverse : relation.last
    def self.find(id)             = relation.where(id: id).first
    def self.find!(id)            = find(id) || raise(ActivePostgrest::RecordNotFound.new(self, id))
    def self.find_by(filters)     = relation.where(filters).first
    def self.find_by!(filters)    = find_by(filters) || raise(ActivePostgrest::RecordNotFound.new(self, filters))

    def self.exists?(filters = {})
      filters.empty? ? relation.any? : relation.where(filters).any?
    end

    def self.pluck(*cols) = relation.pluck(*cols)
    def self.pick(*cols)  = relation.pick(*cols)
    def self.count(mode = :exact) = relation.count(mode)
    def self.any?         = relation.any?
    def self.none?        = relation.none?
    def self.one?         = relation.one?
    def self.many?        = relation.many?

    def initialize(attrs = {})
      types = self.class.attribute_types
      @attributes = attrs.to_h.transform_keys(&:to_s).to_h do |k, v|
        [k, types[k] ? cast_attribute(v, types[k]) : v]
      end
    end

    def [](key) = @attributes[key.to_s]
    attr_reader :attributes

    def to_h = @attributes

    def inspect
      "#<#{self.class.name} #{@attributes.map { "#{_1}: #{_2.inspect}" }.join(', ')}>"
    end

    def method_missing(name, *)
      key = name.to_s
      return @attributes[key] if @attributes.key?(key)

      super
    end

    def respond_to_missing?(name, include_private = false)
      @attributes.key?(name.to_s) || super
    end

    private

    def cast_attribute(value, type)
      return nil if value.nil?

      case type
      when :date then Date.parse(value.to_s)
      when :datetime, :time then Time.parse(value.to_s)
      when :decimal  then BigDecimal(value.to_s)
      when :integer  then Integer(value)
      else value
      end
    end
  end
end
