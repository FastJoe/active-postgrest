# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Evgeny Sokolov (FastJoe)

module ActivePostgrest
  module Mutations
    def create(attrs)
      insert(attrs)
    end

    def create!(attrs)
      insert(attrs) || raise(ActivePostgrest::RecordNotSaved.new(@model_class, attrs))
    end

    def insert(attrs)
      result = @client.post(@table, attrs, prefer: 'return=representation', schema: @schema)
      instantiate_result(result.body)
    end

    def insert_all(records)
      result = @client.post(@table, records, prefer: 'return=representation', schema: @schema)
      instantiate_all(result.body)
    end

    def upsert(attrs)
      result = @client.post(@table, attrs,
                            prefer: 'return=representation,resolution=merge-duplicates',
                            schema: @schema)
      instantiate_result(result.body)
    end

    def upsert_all(records)
      result = @client.post(@table, records,
                            prefer: 'return=representation,resolution=merge-duplicates',
                            schema: @schema)
      instantiate_all(result.body)
    end

    def update_all(attrs)
      return [] if @null

      result = @client.patch(@table, build_params, attrs,
                             prefer: 'return=representation',
                             schema: @schema)
      instantiate_all(result.body)
    end

    def delete_all
      return [] if @null

      result = @client.delete(@table, build_params,
                              prefer: 'return=representation',
                              schema: @schema)
      instantiate_all(result.body)
    end

    private

    def instantiate_all(body)
      Array(body).map { @model_class.new(_1, true, @client) }
    end

    def instantiate_result(body)
      attrs = Array(body).first
      attrs ? @model_class.new(attrs, true, @client) : nil
    end
  end
end
