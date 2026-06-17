# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-06-17

### Added

- `ActivePostgrest::Base` — base class for models with ActiveRecord-style interface
- `ActivePostgrest::Client` — Faraday-based HTTP client with JWT auth and OpenAPI introspection
- `ActivePostgrest::Relation` — immutable query builder (chainable, returns new instances)
- Filtering: `where`, `where.not`, `not_where`, `or_where`, `and_where`
- Filter value encoding: nil → `is.null`, bool → `is.true/false`, Array → `in.(...)`, Range → `gte/lte`, Hash → operator string
- Ordering: `order`, `reorder`; pagination: `limit`, `offset`
- Selection: `select`
- Resource embedding: `joins` (with alias and foreign key support), `embed`
- Retrieval: `all`, `none`, `first`, `last`, `first(n)`, `last(n)`
- Lookup: `find`, `find!`, `find_by`, `find_by!`
- Aggregates: `count`, `any?`, `none?`, `one?`, `many?`
- Projection: `pluck`, `pick`
- Associations: `belongs_to`, `has_many`, `has_one` with auto-generated `with_*` scope methods
- Named scopes via `scope`
- Attribute type casting: `:date` → `Date`, `:datetime`/`:time` → `Time`, `:decimal` → `BigDecimal`, `:integer` → `Integer`
- `POSTGRES_TYPE_CAST` map for PostgreSQL format strings to Ruby types
- Schema introspection: `connection.tables`, `connection.table_schema`, `Model.schema`, `Model.attributes`
- Debugging: `to_url`, `explain`
- `establish_connection` per class with inherited connection fallback
- Rails generator `active_postgrest:model <table>` — generates model and attributes concern from live schema
- `ActivePostgrest::RecordNotFound` error
- RSpec test suite (89 examples)
