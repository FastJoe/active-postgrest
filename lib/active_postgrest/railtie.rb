# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Evgeny Sokolov (FastJoe)

require 'rails/railtie'

module ActivePostgrest
  class Railtie < Rails::Railtie
    initializer 'active_postgrest.active_model' do
      require 'active_postgrest/active_model'
    end
  end
end
