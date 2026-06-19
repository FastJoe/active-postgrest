# active_postgrest

[![Gem Version](https://img.shields.io/gem/v/active_postgrest)](https://rubygems.org/gems/active_postgrest) [![CI](https://github.com/FastJoe/active-postgrest/actions/workflows/ci.yml/badge.svg)](https://github.com/FastJoe/active-postgrest/actions/workflows/ci.yml) [![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE) [![Signed](https://img.shields.io/badge/gem-signed-brightgreen)](certs/gem-public_cert.pem) [![Built with Claude](https://img.shields.io/badge/built%20with-Claude-blueviolet?logo=anthropic)](https://claude.ai)

ActiveRecord-style Ruby client for [PostgREST](https://postgrest.org). [Документация на русском](README.ru.md).

```ruby
User.where(active: true).order(:last_name).limit(20).to_a
User.find!(42)
User.where(age: 18..65).count
User.create!(name: "Alice", email: "alice@example.com")
User.where(active: false).update_all(status: "archived")
```

## PostgREST compatibility

| Feature | Min. PostgREST version |
|---|---|
| Basic queries, filtering, ordering, pagination | 7.0 |
| Mutations — POST, PATCH, DELETE, upsert | 7.0 |
| Multiple schemas (`Accept-Profile` / `Content-Profile`) | 7.0 |
| `or=` / `and=` logical operators | 7.0 |
| `count(:planned)` / `count(:estimated)` | 7.0 |
| `explain` — EXPLAIN plan endpoint | **10.0** |
| `spread` — `...table` syntax | **11.0** |
| Column aggregates — `average`, `sum`, `minimum`, `maximum` | **12.0** |

Column aggregates require `db-aggregates-enabled = true` in `postgrest.conf` (PostgREST 12+).

The library is tested against PostgREST 12. It should work with PostgREST 10+ for all features except column aggregates and `spread`. Core querying and mutations work with PostgREST 7+.

## Installation

Requires Ruby 3.2+.

```ruby
gem "active_postgrest", "~> 0.2"
```

## Setup

### Connection

```ruby
# Global connection via environment variable POSTGREST_URL
class ApplicationRecord < ActivePostgrest::Base
  establish_connection url: "http://localhost:3000", jwt_token: ENV["POSTGREST_JWT"]
end

class User < ApplicationRecord; end
class Company < ApplicationRecord; end
```

Each subclass inherits the connection from its parent. To use separate PostgREST instances per model, call `establish_connection` on that class directly.

### Authorization

**JWT Bearer token** — pass `jwt_token` to `establish_connection`. Every request from that model will include `Authorization: Bearer <token>`.

```ruby
ApplicationRecord.establish_connection(
  url:       "http://localhost:3000",
  jwt_token: ENV["POSTGREST_JWT"]
)
```

**Anonymous access** — when no token is given (or `jwt_token:` is omitted), requests are sent without an `Authorization` header. PostgREST uses its configured `anon` role.

```ruby
ApplicationRecord.establish_connection(url: "http://localhost:3000")
```

**Per-request anonymous access** — when the default connection is authenticated but a specific query should run as anonymous, call `.anonymous` on any model or relation:

```ruby
# Default connection has a JWT token
ApplicationRecord.establish_connection(url: "...", jwt_token: ENV["POSTGREST_JWT"])

# This query runs without Authorization header
User.anonymous.where(active: true).to_a
User.anonymous.find!(42)
User.where(role: "guest").anonymous.limit(10).to_a
```

**Per-request token** — override the token for a specific query with `.with_token(jwt)`. The global connection is unchanged; only that query uses the given token.

```ruby
User.with_token(current_jwt).where(active: true).to_a
User.with_token(current_jwt).find!(42)
```

This is the key pattern for **Row Level Security (RLS)**. PostgREST forwards JWT claims to PostgreSQL as `request.jwt.claims`, so RLS policies can filter rows based on the current user:

```sql
-- policy applied per-request based on the JWT's user_id claim
CREATE POLICY own_rows ON documents
  USING (owner_id = (current_setting('request.jwt.claims')::json->>'user_id')::int);
```

Without per-request tokens all queries share the same role and RLS cannot distinguish users. With `.with_token`, each query carries the right identity:

```ruby
# config/initializers/postgrest.rb
ApplicationRecord.establish_connection(url: ENV["POSTGREST_URL"])
# no global token — anonymous by default

# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  def postgrest_scope(model)
    model.with_token(postgrest_jwt)
  end

  def postgrest_jwt
    # build a short-lived JWT from the current session
    JWT.encode({ user_id: current_user.id, role: "authenticated" }, ENV["JWT_SECRET"])
  end
end

# app/controllers/documents_controller.rb
def index
  @documents = postgrest_scope(Document).where(status: "published").order(:created_at)
end
```

`.with_token` is chainable and does not mutate the original relation.

**Multiple schemas** — PostgREST can expose several PostgreSQL schemas. Set a default schema on a model, or switch schema per-request.

```ruby
# Default schema for an entire model (sent as Accept-Profile header on every request)
class AnalyticsEvent < ApplicationRecord
  self.schema_name = "analytics"
end

AnalyticsEvent.where(type: "click").count   # Accept-Profile: analytics

# Subclasses inherit the schema
class PageView < AnalyticsEvent; end
PageView.where(path: "/home").to_a          # Accept-Profile: analytics

# Per-request override — does not affect the default connection
User.with_schema("private").where(active: true).to_a   # Accept-Profile: private
User.where(active: true).to_a                           # no Accept-Profile header
```

Both methods are chainable and do not mutate the original relation.

### Model

```ruby
class User < ActivePostgrest::Base
  # Override inferred table name (default: "users")
  self.table_name = "users"
  # Override primary key (default: "id")
  self.primary_key = "id"

  # Declare attribute type casts (optional — untyped attrs pass through as-is)
  attribute :birth_date, :date
  attribute :created_at, :datetime
  attribute :score,      :decimal

  belongs_to :company
  has_many   :posts
  has_one    :profile
end
```

### Generator

Generate a model with attribute declarations pulled from the PostgREST OpenAPI schema:

```
rails g active_postgrest:model users
```

This creates `app/models/concerns/user_attributes.rb` (always overwritten) and
`app/models/user.rb` (only if it doesn't already exist).

## Querying

### Filtering

```ruby
User.where(name: "Alice")             # name=eq.Alice
User.where(deleted_at: nil)           # deleted_at=is.null
User.where(active: true)              # active=is.true
User.where(id: [1, 2, 3])            # id=in.(1,2,3)
User.where(age: 18..30)              # age=gte.18&age=lte.30  (inclusive)
User.where(age: 18...30)             # age=gte.18&age=lt.30   (exclusive end)
User.where(age: { gt: 18, lt: 65 }) # age=gt.18&age=lt.65
User.where.not(name: "Bob")          # name=not.eq.Bob
User.not_where(status: "banned")     # status=not.eq.banned
```

All supported PostgREST operators can be passed via the Hash form:

| Operator | Meaning              |
|----------|----------------------|
| `eq`     | equals               |
| `neq`    | not equals           |
| `lt`     | less than            |
| `lte`    | less than or equal   |
| `gt`     | greater than         |
| `gte`    | greater than or equal|
| `like`   | LIKE pattern         |
| `ilike`  | case-insensitive LIKE|
| `is`     | IS (null, true, false, unknown) |
| `in`     | IN list              |
| `cs`     | contains (jsonb/array) |
| `cd`     | contained by         |
| `fts`    | full-text search     |
| `plfts`  | plain language full-text search |
| `phfts`  | phrase full-text search |
| `wfts`   | websearch full-text search |
| `match`  | POSIX regex (case-sensitive) |
| `imatch` | POSIX regex (case-insensitive) |
| `isdistinct` | IS DISTINCT FROM |
| `ov`     | overlap (arrays/ranges) |
| `sl`     | strictly left of range |
| `sr`     | strictly right of range |
| `nxl`    | does not extend left of range |
| `nxr`    | does not extend right of range |
| `adj`    | adjacent to range |

```ruby
User.where(name: { ilike: "%alice%" })
User.where(tags: { cs: "{ruby,rails}" })
User.where(name: { match: "^A.*son$" })   # POSIX regex
User.where(bio: { wfts: "ruby rails" })   # websearch full-text
```

### OR / AND conditions

**AR-style `.or`** — mirrors ActiveRecord's `where.or`:

```ruby
# Simple OR
User.where(active: true).or(User.where(role: "admin"))
# → or=(active.is.true,role.eq.admin)

# Multiple AND conditions on one side are wrapped automatically
User.where(active: true).where(age: { gt: 18 }).or(User.where(role: "admin"))
# → or=(and(active.is.true,age.gt.18),role.eq.admin)
```

**PostgREST-specific multi-condition helpers:**

```ruby
User.or_where([{ age: { lt: 18 } }, { status: "inactive" }])
# → or=(age.lt.18,status.eq.inactive)

User.and_where([{ age: { gt: 18 } }, { role: "admin" }])
# → and=(age.gt.18,role.eq.admin)
```

> **Security note:** `where`, `or_where`, and `and_where` treat hash **keys** as column names without escaping. Never pass raw user-controlled keys directly:
>
> ```ruby
> # UNSAFE — attacker controls which columns are filtered
> User.where(params[:filters])
>
> # SAFE — developer controls keys, only values come from user input
> User.where(status: params[:status], role: params[:role])
> ```

### Ordering, pagination

```ruby
User.order(:last_name)                          # order=last_name.asc
User.order(:created_at, :desc)                  # order=created_at.desc
User.order(:name, :asc, nulls: :last)           # order=name.asc.nullslast
User.order(:name, :desc, nulls: :first)         # order=name.desc.nullsfirst
User.reorder(:id)                               # replaces any previous order
User.limit(10).offset(20)
```

### Selection

```ruby
User.select(:id, :name, :email)     # select=id,name,email
```

**Spread embeds** — flatten a related table's columns into the parent result instead of nesting them as an object:

```ruby
User.spread(:companies)
# select=...companies
# → { id: 1, name: "Alice", company_id: 5, company_name: "Acme" }
# instead of { id: 1, name: "Alice", companies: { id: 5, name: "Acme" } }

User.select(:id, :name).spread(:companies)
# select=id,name,...companies

User.spread(:companies, :profiles)
# select=...companies,...profiles
```

PostgREST automatically prefixes spread columns with the table name to avoid conflicts.

### Joins and embedding

PostgREST allows embedding related resources in one request.

```ruby
# INNER JOIN — only users that have a matching company (like ActiveRecord default)
User.joins(:companies)
User.joins(:companies, select: [:id, :name])

# LEFT JOIN — all users, company data is nil when no match
User.left_joins(:companies)
User.left_joins(:companies, select: [:id, :name])

# Filter on joined table — AR style
User.joins(:companies).where(companies: { name: "Acme" })
User.joins(:companies).where(companies: { active: true })

# Aliased join with explicit foreign key (self-referential tables)
User.joins(:users, as: :mother, foreign_key: :mother_id)

# Embed via computed relationship name (PostgREST functions)
User.embed(:profile)
User.embed(:profile, fields: [:bio, :avatar])
```

### Scopes

```ruby
class User < ActivePostgrest::Base
  scope :active, -> { where(active: true) }
  scope :admins, -> { where(role: "admin") }
end

User.active.admins.order(:name)
```

## Retrieval

```ruby
User.all                          # Relation (lazy)
User.to_a                         # Array of model instances
User.first                        # first record
User.last                         # last record (ordered by pk desc)
User.first(5)                     # Array of 5
User.last(5)                      # Array of 5 (order preserved)
User.find(42)                     # nil if not found
User.find!(42)                    # raises RecordNotFound if not found
User.find_by(email: "a@b.com")   # nil if not found
User.find_by!(email: "a@b.com")  # raises RecordNotFound if not found
User.none                         # empty relation, no HTTP request made
```

## Aggregates

### Row counting

```ruby
User.count                        # exact COUNT(*) — default
User.any?
User.none?
User.one?
User.many?
User.exists?
User.where(active: true).count
```

`count` accepts an optional mode that controls how PostgREST computes the total:

```ruby
User.count              # :exact   — real COUNT(*), always accurate
User.count(:planned)    # :planned — estimate from query planner (EXPLAIN)
User.count(:estimated)  # :estimated — from pg_class.reltuples, near-instant
```

| Mode | SQL equivalent | Speed | Accuracy |
|---|---|---|---|
| `:exact` | `COUNT(*)` | slow on large tables | exact |
| `:planned` | `EXPLAIN SELECT …` | fast | approximate, respects filters |
| `:estimated` | `pg_class.reltuples` | instant | approximate, ignores filters |

`:planned` and `:estimated` return approximate values — PostgREST signals this with a `~` prefix in the `Content-Range` header (`0-24/~1050`), which the library strips automatically.

Use `:exact` (default) when the number must be precise. Use `:planned` for paginated UIs where an estimate per-query is good enough. Use `:estimated` for dashboard counters on tables with millions of rows where a rough total suffices.

`any?`, `none?`, `exists?` use a HEAD request — no count, no response body. `one?`, `many?` use `LIMIT 2`.

### Column aggregates

```ruby
User.average(:age)                # => BigDecimal("32.4")
User.sum(:score)                  # => 15000
User.minimum(:age)                # => 18
User.maximum(:age)                # => 75

# Filters are respected
User.where(active: true).average(:age)
User.joins(:companies).where(companies: { name: "Acme" }).maximum(:score)
```

> **PostgREST configuration required:** column aggregates use PostgREST's aggregate API, which is
> **disabled by default**. Add this to your `postgrest.conf`:
>
> ```
> db-aggregates-enabled = true
> ```
>
> Without it, PostgREST returns an error on aggregate requests.

## Pluck / pick

```ruby
User.pluck(:id)                   # [1, 2, 3, ...]
User.pluck(:id, :name)            # [[1, "Alice"], [2, "Bob"], ...]
User.pick(:email)                 # "alice@example.com" (first match)
```

## Mutations

### Create

```ruby
# Returns a persisted instance (or nil on empty response)
User.create(name: "Alice", email: "alice@example.com")

# Raises if creation fails: UnprocessableEntity on constraint violations (422),
# RecordNotSaved if PostgREST returns no body
User.create!(name: "Alice")

# Bulk insert — returns array of persisted records
User.insert_all([{ name: "Alice" }, { name: "Bob" }])
```

`insert` is the low-level alternative to `create` — same HTTP call, same return value. Use `create` / `create!` for the ActiveRecord-style pattern.

### Upsert

```ruby
# Single upsert — uses PostgREST resolution=merge-duplicates
User.upsert(id: 1, name: "Alice Updated")

# Bulk upsert
User.upsert_all([
  { id: 1, name: "Alice Updated" },
  { id: 2, name: "Bob New" }
])
```

### Update

```ruby
# Bulk — updates all matching rows, returns updated records
User.where(active: false).update_all(status: "archived")
User.where(role: "trial").update_all(expires_at: 30.days.from_now)

# Instance
user = User.find!(1)
user.update(name: "New Name")   # merges attrs and saves
user.name = "Other"
user.save                        # returns true/false
```

### Delete

```ruby
# Bulk — deletes all matching rows, returns deleted records
User.where(created_at: ..1.year.ago).delete_all
User.where(active: false).delete_all

# Instance
user.destroy          # DELETE by primary key; record is marked as destroyed
user.destroyed?       # => true
user.persisted?       # => false
user.save             # => false (destroyed records cannot be re-inserted this way)
```

### Reload

```ruby
user = User.find!(1)
user.name = "Local change"
user.reload   # re-fetches from DB, discards local changes
```

### Persistence state

```ruby
User.new(name: "Alice").new_record?   # => true
User.find!(1).persisted?              # => true

user = User.new(name: "Alice")
user.save          # inserts, marks as persisted
user.persisted?    # => true

user.destroy
user.destroyed?    # => true
user.new_record?   # => false
```

### Write path notes

**Embedded associations are excluded from saves.** `save` and `update` only send scalar (non-Hash, non-Array) attributes to PostgREST. Embedded association data loaded via `with_*` is automatically excluded from the PATCH body — PostgREST would reject non-column keys with a 400 error.

**Token/anonymous context is preserved.** Records returned from queries remember the client they were fetched with. Instance methods `save`, `update`, `destroy`, and `reload` reuse that same client, so RLS policies applied during the read are also applied during writes.

```ruby
# Both GET and PATCH run under user_jwt
user = User.with_token(user_jwt).find!(1)
user.update(name: "New Name")   # uses user_jwt, not the class default connection
```

**`save` returns false for 0 updated rows.** If PostgREST returns an empty response after a PATCH (e.g. the row is invisible under RLS after the write), `save` returns `false` even though the write may have committed. Use `create!` or validate via `find!` after save when strong guarantees are needed.

**`create` / `create!` are chainable on relations.** Call them on any relation, including per-request token scopes:

```ruby
User.with_token(user_jwt).create!(name: "Alice")   # INSERT under user_jwt
```

## ActiveModel (optional)

`active_postgrest` does not depend on ActiveModel. Opt in to get `valid?`, `errors`, and Rails form-helper support (`form_with`).

**Outside Rails** — require after the gem:

```ruby
require 'active_postgrest'
require 'active_postgrest/active_model'
```

**In Rails** — require the railtie (e.g. in an initializer):

```ruby
require 'active_postgrest/railtie'
```

Add `gem "activemodel"` to your Gemfile if it is not already pulled in by Rails.

Once loaded:

```ruby
class User < ActivePostgrest::Base
  validates :name, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
end

user = User.new(email: "bad")
user.valid?           # => false
user.errors[:name]    # => ["can't be blank"]
user.save             # => false — validation failed, no HTTP request made

user = User.new(name: "Alice", email: "alice@example.com")
user.save             # => true — validates then POST
```

`form_with(model: @user)` works because `Base` gets `ActiveModel::Naming` and `ActiveModel::Conversion`.

## Associations

Associations wrap embedded JSON returned by PostgREST — they do **not** trigger additional HTTP requests.

```ruby
class User < ActivePostgrest::Base
  belongs_to :company
  belongs_to :mother, class_name: "User", foreign_key: :mother_id
  has_many   :posts
  has_one    :profile
end
```

Each association declaration also defines a `with_*` class method for eager loading:

```ruby
User.with_company                        # joins companies
User.with_company(fields: [:id, :name])  # joins companies, select id,name
User.with_posts
User.with_mother                         # aliased self-join
```

Data must be embedded in the response — call `with_*` or `joins`/`embed` first:

```ruby
user = User.with_company.find!(1)
user.company.name   # works — company data was embedded
```

## Attribute casting

Declare attribute types to get automatic casting from the string values returned by PostgREST:

| Type        | Ruby class   |
|-------------|--------------|
| `:date`     | `Date`       |
| `:datetime` | `Time`       |
| `:time`     | `Time`       |
| `:decimal`  | `BigDecimal` |
| `:integer`  | `Integer`    |

Undeclared attributes pass through as-is (usually `String`, `Integer`, `nil`).

The generator maps PostgreSQL format strings to types automatically using `POSTGRES_TYPE_CAST`:

| PostgreSQL format               | type        |
|---------------------------------|-------------|
| `date`                          | `:date`     |
| `timestamp`, `timestamp with/without time zone` | `:datetime` |
| `time`, `time with/without time zone`           | `:time`     |
| `numeric`, `decimal`, `real`, `double precision`| `:decimal`  |

## Schema introspection

```ruby
# Via connection object
User.connection.tables          # ["users", "companies", ...]
User.connection.table_schema("users")  # raw OpenAPI definition hash

# Via model
User.schema                     # raw definition hash
User.attributes                 # { "id" => "integer", "name" => "text", ... }
```

## Debugging

```ruby
User.where(active: true).limit(10).to_url
# => "http://localhost:3000/users?active=is.true&limit=10"

User.joins(:companies).where(active: true).to_sql
# => "SELECT *, companies!inner(*)\nFROM users\nWHERE active IS TRUE"
# Reconstructed from relation state — no HTTP call. See method docs for limitations.

User.where(active: true).explain
# Returns PostgREST EXPLAIN plan (requires PostgREST ≥ 10)
```

## Errors

| Class                                  | HTTP | When raised                                         |
|----------------------------------------|------|-----------------------------------------------------|
| `ActivePostgrest::RecordNotFound`      | —    | `find!` or `find_by!` returns no results            |
| `ActivePostgrest::RecordNotSaved`      | —    | `create!` when PostgREST returns no body            |
| `ActivePostgrest::CountNotAvailable`   | —    | `count`, `any?`, `none?`, `one?`, `many?` when PostgREST suppresses `Content-Range` |
| `ActivePostgrest::BadRequest`          | 400  | Malformed query or filter                           |
| `ActivePostgrest::Unauthorized`        | 401  | Missing or invalid JWT token                        |
| `ActivePostgrest::Forbidden`           | 403  | Role lacks permission (RLS / GRANT)                 |
| `ActivePostgrest::ResourceNotFound`    | 404  | Table or schema not found                           |
| `ActivePostgrest::Conflict`            | 409  | Unique constraint violation                         |
| `ActivePostgrest::UnprocessableEntity` | 422  | FK violation, NOT NULL, check constraint            |
| `ActivePostgrest::ServerError`         | 5xx  | PostgREST or PostgreSQL internal error              |
| `KeyError`                             | —    | `POSTGREST_URL` env var missing and no explicit URL |
| `Faraday::Error` (and subclasses)      | —    | Network-level failure                               |

All `ActivePostgrest::Error` subclasses expose `#http_status`, `#code`, `#details`, and `#hint` from the PostgREST error response body.

## Limitations

- **No `distinct`** — PostgREST does not expose a `DISTINCT` modifier. Use a database view instead.
- **No `group` / `having`** — aggregate SQL clauses are not supported by the PostgREST REST API.
- **No lazy association loading** — associations only work when the related data is embedded in the same response via `joins` / `embed` / `with_*`.
- **`to_sql`** — reconstructs an approximate SQL string from the relation state, no database call needed. It uses PostgREST embed notation (`companies!inner(*)`) rather than real SQL joins, and shows literal values instead of `$1`-style placeholders. Use `explain` to see the actual execution plan.
- **`explain`** — requires PostgREST ≥ 10.
- **`count`, `any?`, `none?`, `one?`, `many?`** rely on the `Content-Range` header. If PostgREST is configured to suppress it, all five raise `CountNotAvailable`. `:planned` and `:estimated` modes for `count` return approximate values and are faster but not suitable where precision matters.

## Differences from ActiveRecord

This library intentionally mirrors ActiveRecord's query API, but there are places where it diverges — either because PostgREST works differently, or to expose PostgREST-specific capabilities.

### Same as ActiveRecord

```ruby
User.where(active: true)
User.where(age: { gt: 18 })
User.where(companies: { name: "Acme" })   # AR-style join filter
User.where.not(name: "Bob")
User.joins(:companies)                     # INNER JOIN
User.left_joins(:companies)               # LEFT JOIN
User.order(:name, :desc)
User.limit(10).offset(20)
User.select(:id, :name)
User.find(1) / find!(1) / find_by / find_by!
User.count / any? / none? / one? / many? / exists?
User.average(:age) / sum(:amount) / minimum(:age) / maximum(:age)
User.pluck(:name) / pick(:name)
User.first / last
User.scope :active, -> { where(active: true) }
User.create / create! / insert / insert_all / upsert / upsert_all
User.where(...).update_all / delete_all
user.save / update / destroy / reload
User.where(a: 1).or(User.where(b: 2))       # AR-style OR
```

### Different from ActiveRecord

**OR / AND conditions** — `.or` works the same as AR. `or_where` and `and_where` are PostgREST-specific helpers for multi-condition arrays:

```ruby
# Same as AR — chaining where + or
User.where(active: true).or(User.where(role: "admin"))
User.where(active: true).where(age: { gt: 18 }).or(User.where(role: "admin"))

# PostgREST-specific — pass an array of conditions
User.or_where([{ age: 18 }, { role: "admin" }])
User.and_where([{ age: { gt: 18 } }, { active: true }])
```

**Nulls placement in order** — AR requires raw SQL, здесь keyword:

```ruby
# AR
User.order(Arel.sql("name ASC NULLS LAST"))

# active_postgrest
User.order(:name, :asc, nulls: :last)
```

**Regex filters** — AR requires raw SQL, здесь hash operator:

```ruby
# AR
User.where("name ~ ?", "^A")

# active_postgrest
User.where(name: { match: "^A" })
User.where(name: { imatch: "^a" })   # case-insensitive
```

**`to_sql`** — AR returns the actual SQL sent to the database. Here it reconstructs an approximate representation from the relation's state — no database call, but uses PostgREST embed notation instead of real SQL JOINs:

```ruby
User.joins(:companies).where(active: true).to_sql
# => "SELECT *, companies!inner(*)\nFROM users\nWHERE active IS TRUE"
```

Use `explain` to see the real execution plan.

### PostgREST-specific (no AR equivalent)

```ruby
User.embed(:profile, fields: [:bio])              # computed relationship embedding
User.joins(:companies, where: { active: true })   # join-level filter shorthand
User.where(active: true).to_url                   # inspect the generated URL
User.where(active: true).explain                  # PostgREST EXPLAIN plan
User.with_schema("analytics").where(active: true) # per-request schema switch
User.count(:planned)                              # approximate count from query planner
User.count(:estimated)                            # near-instant count from pg_class
```

### Not implemented

- **`distinct`** — not exposed by PostgREST's REST API. Use a database view instead.
- **`group` / `having`** — not supported by PostgREST's REST API.
- **Lazy association loading** — associations only work when the related data was embedded in the same response via `joins` / `embed` / `with_*`. There is no `user.company` auto-fetch.

## Acknowledgements

This library was designed and built with the assistance of [Claude](https://claude.ai) (Anthropic). The architecture, implementation, and tests were developed through a human–AI collaborative workflow using [Claude Code](https://claude.ai/code).
