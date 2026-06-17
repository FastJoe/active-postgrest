# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Evgeny Sokolov (FastJoe)

module ActivePostgrest
  class Error < StandardError
    attr_reader :code, :details, :hint, :http_status

    def initialize(response)
      body         = response.body.is_a?(Hash) ? response.body : {}
      @http_status = response.status
      @code        = body['code']
      @details     = body['details']
      @hint        = body['hint']
      super(body['message'] || "HTTP #{response.status}")
    end
  end

  # 400
  class BadRequest          < Error; end
  # 401
  class Unauthorized        < Error; end
  # 403
  class Forbidden           < Error; end
  # 404 — таблица/схема не найдена
  class ResourceNotFound    < Error; end
  # 409 — unique violation
  class Conflict            < Error; end
  # 422 — FK, not null, check
  class UnprocessableEntity < Error; end
  # 5xx
  class ServerError         < Error; end
end
