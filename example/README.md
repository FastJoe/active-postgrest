# PostgREST Rails Client

ActiveRecord-style Ruby client for [PostgREST](https://postgrest.org).

## Query Interface

### Basic filtering

```ruby
User.where(name: "John")          # name=eq.John
User.where(name: nil)             # name=is.null
User.where(active: true)          # active=is.true
User.where(active: false)         # active=is.false
```

### Array (IN)

```ruby
User.where(id: [1, 2, 3])         # id=in.(1,2,3)
```

### Range

```ruby
User.where(age: 18..30)           # age=gte.18&age=lte.30
User.where(age: 18...30)          # age=gte.18&age=lt.30
User.where(age: 18..)             # age=gte.18
User.where(age: ..30)             # age=lte.30
```

### Explicit operator

Передавай любой PostgREST-оператор через Hash `{ operator: value }`:

```ruby
User.where(age: { gt: 18 })                  # age=gt.18
User.where(age: { gte: 18, lte: 65 })        # age=gte.18&age=lte.65
User.where(name: { like: "J*" })             # name=like.J*
User.where(name: { ilike: "*john*" })        # name=ilike.*john*
User.where(name: { match: "^J" })            # name=match.^J
User.where(name: { imatch: "^j" })           # name=imatch.^j
User.where(name: { neq: "John" })            # name=neq.John
User.where(name: { isdistinct: nil })        # name=isdistinct.null
User.where(bio: { fts: "ruby rails" })       # bio=fts.ruby rails
User.where(bio: { plfts: "ruby rails" })     # bio=plfts.ruby rails
User.where(bio: { phfts: "ruby rails" })     # bio=phfts.ruby rails
User.where(bio: { wfts: "ruby rails" })      # bio=wfts.ruby rails
User.where(tags: { cs: "{ruby,rails}" })     # tags=cs.{ruby,rails}
User.where(tags: { cd: "{ruby,rails}" })     # tags=cd.{ruby,rails}
User.where(period: { ov: "[2020-01-01,2020-12-31]" })  # period=ov.[2020-01-01,2020-12-31]
User.where(range: { sl: "(1,10)" })          # range=sl.(1,10)
User.where(range: { sr: "(1,10)" })          # range=sr.(1,10)
User.where(range: { nxr: "(1,10)" })         # range=nxr.(1,10)
User.where(range: { nxl: "(1,10)" })         # range=nxl.(1,10)
User.where(range: { adj: "(1,10)" })         # range=adj.(1,10)
```

### Модификаторы ALL / ANY

```ruby
User.where(scores: { "all.gt" => 90 })       # scores=all.gt.90
User.where(scores: { "any.lt" => 50 })       # scores=any.lt.50
```

### Отрицание (NOT)

```ruby
User.where.not(name: "John")                 # name=not.eq.John
User.where.not(age: { gt: 18 })              # age=not.gt.18
User.where.not(id: [1, 2, 3])               # id=not.in.(1,2,3)
User.where.not(name: nil)                    # name=not.is.null
```

### Логические операторы OR / AND

```ruby
# or=(age.lt.18,status.eq.active)
User.or_where([{ age: { lt: 18 } }, { status: "active" }])

# and=(age.gt.18,role.eq.admin)
User.and_where([{ age: { gt: 18 } }, { role: "admin" }])
```

OR и AND можно комбинировать с обычными фильтрами:

```ruby
User.where(company_id: 5).or_where([{ age: { lt: 18 } }, { role: "guest" }])
# company_id=eq.5&or=(age.lt.18,role.eq.guest)
```

### Цепочки и скоупы

```ruby
User.where(active: true).where(age: { gte: 18 }).order(:name).limit(10)

class User < PostgrestRecord
  def self.adults = where(age: { gte: 18 })
  def self.active = where(active: true)
end

User.adults.active.order(:name)
```

### Joins (embedded resources)

```ruby
User.joins(:company, select: [:id, :name])
User.joins(:addresses, as: :home, foreign_key: :home_address_id, select: [:city])
User.joins(:posts, where: { published: true })
```

### Остальные методы

```ruby
User.select(:id, :name, :email)
User.order(:created_at, :desc)
User.limit(20).offset(40)
User.count
User.first
User.all.to_a
User.where(id: 1).to_url    # строка URL с параметрами
User.where(id: 1).to_sql    # SQL через pg_stat_statements
User.where(id: 1).explain   # план запроса PostgREST
```

## Конфигурация

```
POSTGREST_URL=http://localhost:3000
```

Модели наследуются от `PostgrestRecord`:

```ruby
class User < PostgrestRecord
  # table_name по умолчанию: "users"
end

class BlogPost < PostgrestRecord
  self.table_name = "posts"
end
```
