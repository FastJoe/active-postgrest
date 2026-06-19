# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.3] - 2026-06-20

### Fixed

- `attribute_types` is now inherited by subclasses — `attribute` declarations on a parent model no longer need to be repeated on each subclass
- Declared attributes (via `attribute`) now return `nil` and accept setters even when absent from the API response (e.g. after a partial `select`) — previously raised `NoMethodError`

### Changed

- Minimum Ruby version raised to 3.2

## [0.2.2] - 2026-06-20

### Fixed

- `any?`, `none?`, `exists?` now send a HEAD request instead of `COUNT(*)` — no body is transferred, no full-table scan on large tables
- `one?`, `many?` now use `LIMIT 2` instead of `COUNT(*)` — orders of magnitude faster on large tables
- Column aggregates (`average`, `sum`, `minimum`, `maximum`) now return numeric Ruby types instead of `String`: decimal values return `BigDecimal`, whole-number values return `Integer`

## [0.2.1] - 2026-06-18

### Added

- Mutations: `create`, `create!`, `insert`, `insert_all`, `upsert`, `upsert_all`, `update_all`, `delete_all` as class and relation methods
- Instance persistence: `save`, `update`, `destroy`, `reload`
- Persistence state predicates: `new_record?`, `persisted?`, `destroyed?`
- Attribute setters via `method_missing` (`record.name = "x"`) and `[]=`; both apply declared type casting
- `Relation#or` — AR-style OR combining two relations (`where(a: 1).or(where(b: 2))`)
- LEFT JOIN support via `left_joins` (previously only `joins` / INNER JOIN was available)
- Optional ActiveModel integration: `require 'active_postgrest/active_model'` adds `Validations`, `Naming`, `Conversion`; `require 'active_postgrest/railtie'` auto-loads in Rails
- `ActivePostgrest::Mutations` module (included into `Relation`)
- `Client#post`, `#patch`, `#delete` HTTP methods
- `ActivePostgrest::RecordNotSaved` error raised by `create!` when PostgREST returns no body
- `RecordNotFound` and `CountNotAvailable` moved from `relation.rb` to `errors.rb`
- PostgREST compatibility table in README

### Fixed

- `save` / `update` no longer send embedded association data (Hash/Array attributes) in the PATCH body; only scalar attributes are sent
- Token / anonymous context is now preserved across instance writes: records remember the client they were loaded with; `save`, `update`, `destroy`, `reload` reuse that client so RLS policies stay consistent between read and write
- `create` / `create!` now available directly on `Relation` — `Model.with_token(jwt).create!(attrs)` works without falling back to the default connection
- `Relation#or` now raises `ArgumentError` if the receiver already has `or_where` / `and_where` conditions (previously only the argument side was checked)
- `has_many` embedded associations now handle a single embedded object returned as a Hash instead of an Array
- `belongs_to` / `has_one` / `has_many` embedded records are now instantiated as persisted
- `destroy` no longer sets `new_record? = true`; after destroy: `destroyed? = true`, `new_record? = false`, `persisted? = false`
- `destroy` and `save` (persisted branch) raise `ArgumentError` when the primary key value is nil
- `to_sql` correctly renders `and(...)` groups produced by `Relation#or`
- ActiveModel `valid?` no longer raises `NoMethodError` for attributes absent from the initial hash
- Records returned from `to_a` and all mutation methods are now instantiated as persisted

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
