# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Evgeny Sokolov (FastJoe)

module ActivePostgrest
  class RecordNotFound < StandardError
    def initialize(model, id)
      super("#{model.name} not found: #{id.inspect}")
    end
  end

  class CountNotAvailable < StandardError; end

  class Relation
    include Enumerable

    class WhereChain
      def initialize(relation)
        @relation = relation
      end

      def not(filters)
        @relation.not_where(filters)
      end
    end

    def initialize(table, client, model_class)
      @table = table
      @client = client
      @model_class = model_class
      @selects = []
      @joins = []
      @filters = {}
      @or_conditions = []
      @and_conditions = []
      @limit_val = nil
      @offset_val = nil
      @order_val = nil
      @null = false
      @schema = nil
    end

    def select(*cols)
      clone_with { @selects.concat(cols.map(&:to_s)) }
    end

    def spread(*tables)
      clone_with { @selects.concat(tables.map { "...#{_1}" }) }
    end

    # joins(:companies)                                      → INNER JOIN (excludes rows with no match)
    # joins(:users, as: :mother, foreign_key: :mother_id)  → aliased FK join
    def joins(table, as: nil, foreign_key: nil, select: [], where: {})
      embed = build_embed(table.to_s, as&.to_s, foreign_key&.to_s, inner: true)
      add_embed(embed, table.to_s, select.map(&:to_s), where)
    end

    # left_joins(:companies) → LEFT JOIN (includes rows even with no match)
    def left_joins(table, as: nil, foreign_key: nil, select: [], where: {})
      embed = build_embed(table.to_s, as&.to_s, foreign_key&.to_s, inner: false)
      add_embed(embed, table.to_s, select.map(&:to_s), where)
    end

    # embed(:mother, fields: [:id, :first_name]) — computed relationship
    def embed(name, fields: [])
      add_embed(name.to_s, name.to_s, fields.map(&:to_s), {})
    end

    # where(name: "John")                         → name=eq.John
    # where(name: nil)                             → name=is.null
    # where(active: true)                          → active=is.true
    # where(id: [1, 2, 3])                         → id=in.(1,2,3)
    # where(age: 18..30)                           → age=gte.18&age=lte.30
    # where(age: { gt: 18, lt: 65 })              → age=gt.18&age=lt.65
    # where(companies: { name: "Acme" })           → companies.name=eq.Acme  (AR-style joins filter)
    # where.not(name: "John")                      → name=not.eq.John
    def where(filters = nil)
      return WhereChain.new(self) if filters.nil?

      clone_with { encode_filters!(filters) }
    end

    def not_where(filters)
      clone_with { encode_filters!(filters, negate: true) }
    end

    # or_where([{ age: { lt: 18 } }, { status: "active" }]) → or=(age.lt.18,status.eq.active)
    def or_where(conditions)
      parts = Array(conditions).flat_map { |f| condition_parts(f) }
      clone_with { @or_conditions.concat(parts) }
    end

    # and_where([{ age: { gt: 18 } }, { status: "active" }]) → and=(age.gt.18,status.eq.active)
    def and_where(conditions)
      parts = Array(conditions).flat_map { |f| condition_parts(f) }
      clone_with { @and_conditions.concat(parts) }
    end

    def limit(n)       = clone_with { @limit_val = n }
    def offset(n)      = clone_with { @offset_val = n }

    def order(col, dir = :asc, nulls: nil)
      clone_with { @order_val = build_order(col, dir, nulls) }
    end

    def reorder(col, dir = :asc, nulls: nil)
      clone_with { @order_val = build_order(col, dir, nulls) }
    end

    def none                 = clone_with { @null = true }
    def anonymous            = clone_with { @client = @client.anonymous }
    def with_token(jwt)      = clone_with { @client = @client.with_token(jwt) }
    def with_schema(name)    = clone_with { @schema = name }

    def each(&)
      to_a.each(&)
    end

    def to_a
      return [] if @null

      Array(@client.get(@table, build_params, schema: @schema).body).map { |attrs| @model_class.new(attrs) }
    end

    def first
      limit(1).to_a.first
    end

    def last(n = nil)
      pk = @model_class.primary_key
      return order(pk, :desc).limit(n).to_a.reverse if n

      order(pk, :desc).limit(1).to_a.first
    end

    def count(mode = :exact)
      return 0 if @null

      response = @client.get(@table, build_params.merge(limit: 0), count: mode, schema: @schema)
      raw   = response.headers['content-range']&.split('/')&.last
      total = raw&.delete_prefix('~')
      if total.nil? || total == '*'
        raise CountNotAvailable, "count=#{mode} not available (Content-Range: #{raw.inspect})"
      end

      total.to_i
    end

    def any?(&block)    = block ? super : count.positive?
    def none?(&block)   = block ? super : count.zero?
    def one?(&block)    = block ? super : count == 1
    def many?           = count > 1
    def exists?         = any?

    def average(col)  = aggregate_value("#{col}.avg()", 'avg')
    def sum(col)      = aggregate_value("#{col}.sum()", 'sum')
    def minimum(col)  = aggregate_value("#{col}.min()", 'min')
    def maximum(col)  = aggregate_value("#{col}.max()", 'max')

    def pluck(*cols)
      return [] if @null

      select(*cols).to_a.map do |record|
        cols.length == 1 ? record[cols.first] : cols.map { record[_1] }
      end
    end

    def pick(*cols)
      pluck(*cols).first
    end

    # Returns a human-readable SQL-like representation of the query reconstructed
    # from the relation's internal state — no database call is made.
    #
    # Limitations vs actual SQL:
    # - Embedded resources use PostgREST notation: companies(*) instead of
    #   LEFT JOIN companies ON companies.id = users.company_id.
    # - Parameters are shown as literal values, not PostgreSQL placeholders ($1, $2).
    # - The actual query PostgREST sends is a CTE (WITH pgrst_source AS (...))
    #   and may differ in structure. Use #explain to see the real execution plan.
    def to_sql
      clauses = ["SELECT #{sql_select}", "FROM #{@table}"]

      wheres = sql_where_clauses
      clauses << "WHERE #{wheres.join("\n  AND ")}" if wheres.any?

      clauses << "ORDER BY #{sql_order}" if @order_val
      clauses << "LIMIT #{@limit_val}"   if @limit_val
      clauses << "OFFSET #{@offset_val}" if @offset_val

      clauses.join("\n")
    end

    def explain
      @client.explain(@table, build_params, schema: @schema)
    end

    def to_url
      params = build_params
      base   = "#{@client.base_url}/#{@table}"
      return base if params.empty?

      query  = params.flat_map { |k, v| Array(v).map { "#{k}=#{_1}" } }.join('&')
      "#{base}?#{query}"
    end

    def method_missing(name, *, **)
      return super unless @model_class.respond_to?(name)

      scope = @model_class.public_send(name, *, **)
      return super unless scope.is_a?(ActivePostgrest::Relation)

      merge(scope)
    end

    def respond_to_missing?(name, include_private = false)
      @model_class.respond_to?(name) || super
    end

    def inspect
      to_a.inspect
    end

    include SqlBuilder

    private

    def merge(other)
      clone_with do
        @selects.concat(other.instance_variable_get(:@selects))
        @joins.concat(other.instance_variable_get(:@joins))
        other.instance_variable_get(:@filters).each { |k, v| merge_filter!(k, v) }
        @or_conditions.concat(other.instance_variable_get(:@or_conditions))
        @and_conditions.concat(other.instance_variable_get(:@and_conditions))
        @limit_val  = other.instance_variable_get(:@limit_val)  if other.instance_variable_get(:@limit_val)
        @offset_val = other.instance_variable_get(:@offset_val) if other.instance_variable_get(:@offset_val)
        @order_val  = other.instance_variable_get(:@order_val)  if other.instance_variable_get(:@order_val)
        @null       = true if other.instance_variable_get(:@null)
      end
    end

    def add_embed(embed_str, table, select, where)
      clone_with { @joins << { embed: embed_str, select: select, where: where, table: table } }
    end

    def build_embed(table, as_name, foreign_key, inner: false)
      embed = as_name ? "#{as_name}:#{table}" : table
      embed += "!#{foreign_key}" if foreign_key
      embed += '!inner' if inner
      embed
    end

    def encode_filters!(filters, negate: false)
      prefix = negate ? 'not.' : ''
      filters.each do |col, val|
        if table_condition?(val)
          val.each do |sub_col, sub_val|
            encoded = encode_value(sub_val, prefix: prefix)
            merge_filter!("#{col}.#{sub_col}", encoded) unless encoded.nil?
          end
        else
          encoded = encode_value(val, prefix: prefix)
          merge_filter!(col.to_s, encoded) unless encoded.nil?
        end
      end
    end

    def aggregate_value(expr, key)
      return nil if @null

      clone_with do
        @selects    = [expr]
        @joins      = []
        @limit_val  = nil
        @offset_val = nil
        @order_val  = nil
      end.to_a.first&.[](key)
    end

    def condition_parts(filters)
      filters.flat_map do |col, val|
        Array(encode_value(val)).map { "#{col}.#{_1}" }
      end
    end

    def build_params
      params = {}
      params[:select] = build_select if @selects.any? || @joins.any?
      params[:order]  = @order_val if @order_val
      params[:limit]  = @limit_val if @limit_val
      params[:offset] = @offset_val if @offset_val
      params[:or]     = "(#{@or_conditions.join(',')})" if @or_conditions.any?
      params[:and]    = "(#{@and_conditions.join(',')})" if @and_conditions.any?
      params.merge!(@filters)

      @joins.each do |j|
        j[:where].each do |col, val|
          key = "#{j[:table]}.#{col}"
          encoded = encode_value(val)
          existing = params[key]
          params[key] = existing ? [*Array(existing), *Array(encoded)] : encoded
        end
      end

      params
    end

    def build_select
      parts = @selects.empty? ? ['*'] : @selects.dup
      @joins.each do |j|
        inner = j[:select].any? ? j[:select].join(',') : '*'
        parts << "#{j[:embed]}(#{inner})"
      end
      parts.join(',')
    end

    def clone_with(&block)
      dup.tap do |copy|
        copy.instance_variable_set(:@selects, @selects.dup)
        copy.instance_variable_set(:@joins, @joins.dup)
        copy.instance_variable_set(:@filters, @filters.dup)
        copy.instance_variable_set(:@or_conditions, @or_conditions.dup)
        copy.instance_variable_set(:@and_conditions, @and_conditions.dup)
        copy.instance_variable_set(:@null, @null)
        copy.instance_eval(&block)
      end
    end
  end
end
