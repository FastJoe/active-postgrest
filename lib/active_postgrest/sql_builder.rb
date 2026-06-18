# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Evgeny Sokolov (FastJoe)

module ActivePostgrest
  module SqlBuilder
    FILTER_OPS = {
      'eq' => '=', 'neq' => '!=', 'gt' => '>', 'gte' => '>=',
      'lt' => '<', 'lte' => '<=', 'like' => 'LIKE', 'ilike' => 'ILIKE',
      'fts' => '@@', 'cs' => '@>', 'cd' => '<@'
    }.freeze

    NEGATED_OPS = {
      'eq' => '!=', 'neq' => '=', 'gt' => '<=', 'gte' => '<',
      'lt' => '>=', 'lte' => '>', 'like' => 'NOT LIKE', 'ilike' => 'NOT ILIKE'
    }.freeze

    KNOWN_OP_KEYS = (FILTER_OPS.keys + %w[not in is]).freeze

    private

    def table_condition?(val)
      val.is_a?(Hash) && val.keys.none? { KNOWN_OP_KEYS.include?(_1.to_s) }
    end

    def encode_value(val, prefix: '')
      case val
      when nil   then "#{prefix}is.null"
      when true  then "#{prefix}is.true"
      when false then "#{prefix}is.false"
      when Array then "#{prefix}in.(#{val.map { encode_in_value(_1) }.join(',')})"
      when Range
        parts = []
        parts << "#{prefix}gte.#{val.begin}" unless val.begin.nil?
        parts << (val.exclude_end? ? "#{prefix}lt.#{val.end}" : "#{prefix}lte.#{val.end}") unless val.end.nil?
        return nil if parts.empty?

        parts.one? ? parts.first : parts
      when Hash
        parts = val.map { |op, v| "#{prefix}#{op}.#{v}" }
        parts.one? ? parts.first : parts
      else
        "#{prefix}eq.#{val}"
      end
    end

    def encode_in_value(v)
      str = v.to_s
      str.include?(',') ? %("#{str}") : str
    end

    def sql_select
      parts = @selects.empty? ? ['*'] : @selects.dup
      @joins.each do |j|
        cols = j[:select].any? ? j[:select].join(', ') : '*'
        parts << "#{j[:embed]}(#{cols})"
      end
      parts.join(', ')
    end

    def sql_where_clauses
      clauses = @filters.flat_map { |col, encoded| Array(encoded).map { decode_filter(col, _1) } }
      @joins.each do |j|
        j[:where].each do |col, val|
          Array(encode_value(val)).each { |encoded| clauses << decode_filter("#{j[:table]}.#{col}", encoded) }
        end
      end
      clauses << "(#{@or_conditions.map  { decode_condition(_1) }.join(' OR ')})"  if @or_conditions.any?
      clauses << "(#{@and_conditions.map { decode_condition(_1) }.join(' AND ')})" if @and_conditions.any?
      clauses
    end

    def sql_order
      col, dir, nulls = @order_val.split('.')
      nulls_sql = { 'nullslast' => 'NULLS LAST', 'nullsfirst' => 'NULLS FIRST' }[nulls]
      [col, dir&.upcase || 'ASC', nulls_sql].compact.join(' ')
    end

    def build_order(col, dir, nulls)
      val = "#{col}.#{dir}"
      val += ".nulls#{nulls}" if nulls
      val
    end

    def encoded_filter_conditions
      @filters.flat_map { |col, enc| Array(enc).map { "#{col}.#{_1}" } }
    end

    def or_group(conditions)
      return nil if conditions.empty?

      conditions.one? ? conditions.first : "and(#{conditions.join(',')})"
    end

    def condition_parts(filters)
      filters.flat_map do |col, val|
        Array(encode_value(val)).map { "#{col}.#{_1}" }
      end
    end

    def merge_filter!(col, encoded)
      existing = @filters[col]
      @filters[col] = existing ? [*Array(existing), *Array(encoded)] : encoded
    end

    def decode_filter(col, encoded)
      negated = encoded.start_with?('not.')
      rest    = negated ? encoded[4..] : encoded
      op, val = rest.split('.', 2)

      case op
      when 'is' then "#{col} IS#{' NOT' if negated} #{val.upcase}"
      when 'in' then decode_in(col, val, negated)
      else
        sql_op = negated ? (NEGATED_OPS[op] || "NOT #{FILTER_OPS[op] || op}") : (FILTER_OPS[op] || op)
        "#{col} #{sql_op} #{sql_quote(val)}"
      end
    end

    def decode_in(col, val, negated)
      vals = val.delete_prefix('(').delete_suffix(')').split(',').map { |v| sql_quote(v.strip.delete('"')) }
      "#{col} #{'NOT ' if negated}IN (#{vals.join(', ')})"
    end

    def decode_condition(cond)
      if cond.start_with?('and(') && cond.end_with?(')')
        inner = cond[4..-2]
        return "(#{split_conditions(inner).map { decode_condition(_1) }.join(' AND ')})"
      end

      parts  = cond.split('.')
      op_idx = parts.index { KNOWN_OP_KEYS.include?(_1) }
      return cond unless op_idx

      col     = parts[0...op_idx].join('.')
      encoded = parts[op_idx..].join('.')
      decode_filter(col, encoded)
    end

    def split_conditions(str)
      depth  = 0
      start  = 0
      result = []
      str.each_char.with_index do |c, i|
        case c
        when '(' then depth += 1
        when ')' then depth -= 1
        when ','
          if depth.zero?
            result << str[start...i]
            start = i + 1
          end
        end
      end
      result << str[start..]
      result.reject(&:empty?)
    end

    def sql_quote(val)
      return val if val&.match?(/\A-?\d+(\.\d+)?\z/)

      "'#{val.to_s.gsub("'", "''")}'"
    end
  end
end
