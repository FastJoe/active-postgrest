# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Evgeny Sokolov (FastJoe)

require 'active_support'
require 'active_support/core_ext/string'
require 'faraday'
require 'bigdecimal'

require 'active_postgrest/version'
require 'active_postgrest/errors'
require 'active_postgrest/client'
require 'active_postgrest/sql_builder'
require 'active_postgrest/relation'
require 'active_postgrest/base'
