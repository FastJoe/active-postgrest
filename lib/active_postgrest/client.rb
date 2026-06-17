# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Evgeny Sokolov (FastJoe)

module ActivePostgrest
  class Client
    attr_reader :base_url

    def initialize(base_url = ENV.fetch('POSTGREST_URL'), jwt_token = nil)
      @base_url = base_url
      @auth_header = "Bearer #{jwt_token}" if jwt_token
      @conn = Faraday.new(base_url, request: { params_encoder: Faraday::FlatParamsEncoder }) do |f|
        f.request :json
        f.response :json
      end
    end

    def openapi
      @openapi ||= @conn.get('/').body
    end

    def tables
      openapi['paths']&.keys&.filter_map { |p| p.delete_prefix('/').then { |s| s.empty? ? nil : s } } || []
    end

    def table_schema(table)
      openapi.dig('definitions', table) || {}
    end

    def explain(resource, params = {}, schema: nil)
      @conn.get(resource, params) do |req|
        auth_headers(req)
        req.headers['Accept']          = 'application/vnd.pgrst.plan+text; for="application/json"; options=verbose'
        req.headers['Accept-Profile']  = schema if schema
      end.body
    end

    def get(resource, params = {}, count: :exact, schema: nil)
      response = @conn.get(resource, params) do |req|
        auth_headers(req)
        req.headers['Prefer']         = "count=#{count}"
        req.headers['Accept-Profile'] = schema if schema
      end
      raise_on_error!(response)
      response
    end

    def anonymous
      self.class.new(@base_url)
    end

    def with_token(jwt)
      self.class.new(@base_url, jwt)
    end

    private

    def raise_on_error!(response)
      klass = case response.status
              when 400 then BadRequest
              when 401 then Unauthorized
              when 403 then Forbidden
              when 404 then ResourceNotFound
              when 409 then Conflict
              when 422 then UnprocessableEntity
              when 500..599 then ServerError
              end
      raise klass, response if klass
    end

    def auth_headers(req)
      req.headers['Authorization'] = @auth_header if @auth_header
    end
  end
end
