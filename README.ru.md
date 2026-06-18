# active_postgrest

[![Gem Version](https://img.shields.io/gem/v/active_postgrest)](https://rubygems.org/gems/active_postgrest) [![CI](https://github.com/FastJoe/active-postgrest/actions/workflows/ci.yml/badge.svg)](https://github.com/FastJoe/active-postgrest/actions/workflows/ci.yml) [![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE) [![Signed](https://img.shields.io/badge/gem-signed-brightgreen)](certs/gem-public_cert.pem) [![Built with Claude](https://img.shields.io/badge/built%20with-Claude-blueviolet?logo=anthropic)](https://claude.ai)

Ruby-клиент для [PostgREST](https://postgrest.org) в стиле ActiveRecord.

```ruby
User.where(active: true).order(:last_name).limit(20).to_a
User.find!(42)
User.where(age: 18..65).count
User.create!(name: "Alice", email: "alice@example.com")
User.where(active: false).update_all(status: "archived")
```

## Совместимость с PostgREST

| Функция | Мин. версия PostgREST |
|---|---|
| Базовые запросы, фильтрация, сортировка, пагинация | 7.0 |
| Мутации — POST, PATCH, DELETE, upsert | 7.0 |
| Множественные схемы (`Accept-Profile` / `Content-Profile`) | 7.0 |
| Операторы `or=` / `and=` | 7.0 |
| `count(:planned)` / `count(:estimated)` | 7.0 |
| `explain` — EXPLAIN plan endpoint | **10.0** |
| `spread` — синтаксис `...table` | **11.0** |
| Агрегаты по столбцам — `average`, `sum`, `minimum`, `maximum` | **12.0** |

Агрегаты по столбцам требуют `db-aggregates-enabled = true` в `postgrest.conf` (PostgREST 12+).

Библиотека тестировалась с PostgREST 12. Все функции кроме агрегатов по столбцам и `spread` работают с PostgREST 10+. Базовые запросы и мутации работают с PostgREST 7+.

## Установка

```ruby
gem "active_postgrest", "~> 0.2"
```

## Настройка

### Соединение

```ruby
# Глобальное соединение через переменную окружения POSTGREST_URL
class ApplicationRecord < ActivePostgrest::Base
  establish_connection url: "http://localhost:3000", jwt_token: ENV["POSTGREST_JWT"]
end

class User < ApplicationRecord; end
class Company < ApplicationRecord; end
```

Каждый подкласс наследует соединение от родителя. Чтобы использовать отдельный экземпляр PostgREST для конкретной модели, вызовите `establish_connection` непосредственно на ней.

### Авторизация

**JWT Bearer token** — передайте `jwt_token` в `establish_connection`. Каждый запрос этой модели будет содержать заголовок `Authorization: Bearer <token>`.

```ruby
ApplicationRecord.establish_connection(
  url:       "http://localhost:3000",
  jwt_token: ENV["POSTGREST_JWT"]
)
```

**Анонимный доступ** — если токен не передан (или `jwt_token:` не указан), запросы отправляются без заголовка `Authorization`. PostgREST использует настроенную роль `anon`.

```ruby
ApplicationRecord.establish_connection(url: "http://localhost:3000")
```

**Анонимный запрос** — когда соединение по умолчанию аутентифицировано, но конкретный запрос должен выполняться анонимно, вызовите `.anonymous` на модели или relation:

```ruby
# Соединение по умолчанию имеет JWT токен
ApplicationRecord.establish_connection(url: "...", jwt_token: ENV["POSTGREST_JWT"])

# Этот запрос выполняется без заголовка Authorization
User.anonymous.where(active: true).to_a
User.anonymous.find!(42)
User.where(role: "guest").anonymous.limit(10).to_a
```

**Токен на запрос** — переопределите токен для конкретного запроса через `.with_token(jwt)`. Глобальное соединение не меняется; только этот запрос использует переданный токен.

```ruby
User.with_token(current_jwt).where(active: true).to_a
User.with_token(current_jwt).find!(42)
```

Это ключевой паттерн для **Row Level Security (RLS)**. PostgREST передаёт JWT claims в PostgreSQL как `request.jwt.claims`, и политики RLS могут фильтровать строки по текущему пользователю:

```sql
-- политика применяется на основе claim user_id из JWT
CREATE POLICY own_rows ON documents
  USING (owner_id = (current_setting('request.jwt.claims')::json->>'user_id')::int);
```

Без токена на запрос все запросы выполняются с одной ролью и RLS не может различать пользователей. С `.with_token` каждый запрос несёт нужную идентичность:

```ruby
# config/initializers/postgrest.rb
ApplicationRecord.establish_connection(url: ENV["POSTGREST_URL"])
# глобального токена нет — анонимный доступ по умолчанию

# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  def postgrest_scope(model)
    model.with_token(postgrest_jwt)
  end

  def postgrest_jwt
    # короткоживущий JWT из текущей сессии
    JWT.encode({ user_id: current_user.id, role: "authenticated" }, ENV["JWT_SECRET"])
  end
end

# app/controllers/documents_controller.rb
def index
  @documents = postgrest_scope(Document).where(status: "published").order(:created_at)
end
```

`.with_token` поддерживает цепочку вызовов и не мутирует оригинальный relation.

**Множественные схемы** — PostgREST может работать с несколькими PostgreSQL-схемами. Задайте схему по умолчанию на модели или переключайте схему на уровне запроса.

```ruby
# Схема по умолчанию для всей модели (передаётся как Accept-Profile в каждом запросе)
class AnalyticsEvent < ApplicationRecord
  self.schema_name = "analytics"
end

AnalyticsEvent.where(type: "click").count   # Accept-Profile: analytics

# Подклассы наследуют схему
class PageView < AnalyticsEvent; end
PageView.where(path: "/home").to_a          # Accept-Profile: analytics

# Переопределение на уровне запроса — не влияет на соединение по умолчанию
User.with_schema("private").where(active: true).to_a   # Accept-Profile: private
User.where(active: true).to_a                           # без заголовка Accept-Profile
```

Оба метода поддерживают цепочку вызовов и не мутируют оригинальный relation.

### Модель

```ruby
class User < ActivePostgrest::Base
  # Переопределить имя таблицы (по умолчанию: "users")
  self.table_name = "users"
  # Переопределить первичный ключ (по умолчанию: "id")
  self.primary_key = "id"

  # Объявить типы атрибутов (опционально — необъявленные атрибуты передаются как есть)
  attribute :birth_date, :date
  attribute :created_at, :datetime
  attribute :score,      :decimal

  belongs_to :company
  has_many   :posts
  has_one    :profile
end
```

### Генератор

Сгенерировать модель с объявлениями атрибутов из OpenAPI-схемы PostgREST:

```
rails g active_postgrest:model users
```

Создаёт `app/models/concerns/user_attributes.rb` (перезаписывается при каждом запуске) и `app/models/user.rb` (только если файл ещё не существует).

## Запросы

### Фильтрация

```ruby
User.where(name: "Alice")             # name=eq.Alice
User.where(deleted_at: nil)           # deleted_at=is.null
User.where(active: true)              # active=is.true
User.where(id: [1, 2, 3])            # id=in.(1,2,3)
User.where(age: 18..30)              # age=gte.18&age=lte.30  (включительно)
User.where(age: 18...30)             # age=gte.18&age=lt.30   (исключая конец)
User.where(age: { gt: 18, lt: 65 }) # age=gt.18&age=lt.65
User.where.not(name: "Bob")          # name=not.eq.Bob
User.not_where(status: "banned")     # status=not.eq.banned
```

Все операторы PostgREST доступны через Hash-форму:

| Оператор | Значение |
|----------|----------|
| `eq`     | равно |
| `neq`    | не равно |
| `lt`     | меньше |
| `lte`    | меньше или равно |
| `gt`     | больше |
| `gte`    | больше или равно |
| `like`   | LIKE паттерн |
| `ilike`  | LIKE без учёта регистра |
| `is`     | IS (null, true, false, unknown) |
| `in`     | IN список |
| `cs`     | содержит (jsonb/array) |
| `cd`     | содержится в |
| `fts`    | полнотекстовый поиск |
| `plfts`  | полнотекстовый поиск (plain language) |
| `phfts`  | полнотекстовый поиск по фразе |
| `wfts`   | полнотекстовый поиск (websearch) |
| `match`  | POSIX regex (с учётом регистра) |
| `imatch` | POSIX regex (без учёта регистра) |
| `isdistinct` | IS DISTINCT FROM |
| `ov`     | пересечение (массивы/диапазоны) |
| `sl`     | строго левее диапазона |
| `sr`     | строго правее диапазона |
| `nxl`    | не выходит за левую границу диапазона |
| `nxr`    | не выходит за правую границу диапазона |
| `adj`    | смежный с диапазоном |

```ruby
User.where(name: { ilike: "%alice%" })
User.where(tags: { cs: "{ruby,rails}" })
User.where(name: { match: "^A.*son$" })   # POSIX regex
User.where(bio: { wfts: "ruby rails" })   # websearch полнотекстовый
```

### Условия OR / AND

**AR-стиль `.or`** — работает как в ActiveRecord:

```ruby
# Простой OR
User.where(active: true).or(User.where(role: "admin"))
# → or=(active.is.true,role.eq.admin)

# Несколько AND-условий слева оборачиваются автоматически
User.where(active: true).where(age: { gt: 18 }).or(User.where(role: "admin"))
# → or=(and(active.is.true,age.gt.18),role.eq.admin)
```

**Специфичные для PostgREST хелперы с массивом условий:**

```ruby
User.or_where([{ age: { lt: 18 } }, { status: "inactive" }])
# → or=(age.lt.18,status.eq.inactive)

User.and_where([{ age: { gt: 18 } }, { role: "admin" }])
# → and=(age.gt.18,role.eq.admin)
```

> **Важно (безопасность):** `where`, `or_where` и `and_where` используют ключи хэша как имена колонок без экранирования. Никогда не передавайте пользовательские ключи напрямую:
>
> ```ruby
> # НЕБЕЗОПАСНО — атакующий контролирует имена колонок в фильтре
> User.where(params[:filters])
>
> # БЕЗОПАСНО — ключи задаёт разработчик, от пользователя приходят только значения
> User.where(status: params[:status], role: params[:role])
> ```

### Сортировка и пагинация

```ruby
User.order(:last_name)                          # order=last_name.asc
User.order(:created_at, :desc)                  # order=created_at.desc
User.order(:name, :asc, nulls: :last)           # order=name.asc.nullslast
User.order(:name, :desc, nulls: :first)         # order=name.desc.nullsfirst
User.reorder(:id)                               # заменяет предыдущую сортировку
User.limit(10).offset(20)
```

### Выборка столбцов

```ruby
User.select(:id, :name, :email)     # select=id,name,email
```

**Spread embeds** — развернуть столбцы связанной таблицы в плоский объект вместо вложенного:

```ruby
User.spread(:companies)
# select=...companies
# → { id: 1, name: "Alice", company_id: 5, company_name: "Acme" }
# вместо { id: 1, name: "Alice", companies: { id: 5, name: "Acme" } }

User.select(:id, :name).spread(:companies)
# select=id,name,...companies

User.spread(:companies, :profiles)
# select=...companies,...profiles
```

PostgREST автоматически добавляет префикс с именем таблицы к развёрнутым столбцам, чтобы избежать конфликтов имён.

### Джойны и встраивание

PostgREST позволяет встраивать связанные ресурсы в один запрос.

```ruby
# INNER JOIN — только пользователи с соответствующей компанией (как по умолчанию в ActiveRecord)
User.joins(:companies)
User.joins(:companies, select: [:id, :name])

# LEFT JOIN — все пользователи, данные компании nil если нет совпадения
User.left_joins(:companies)
User.left_joins(:companies, select: [:id, :name])

# Фильтр по связанной таблице — в стиле AR
User.joins(:companies).where(companies: { name: "Acme" })
User.joins(:companies).where(companies: { active: true })

# Псевдоним джойна с явным внешним ключом (самореферентные таблицы)
User.joins(:users, as: :mother, foreign_key: :mother_id)

# Встраивание через имя вычисленной связи (PostgREST-функции)
User.embed(:profile)
User.embed(:profile, fields: [:bio, :avatar])
```

### Скоупы

```ruby
class User < ActivePostgrest::Base
  scope :active, -> { where(active: true) }
  scope :admins, -> { where(role: "admin") }
end

User.active.admins.order(:name)
```

## Получение данных

```ruby
User.all                          # Relation (ленивый)
User.to_a                         # массив экземпляров модели
User.first                        # первая запись
User.last                         # последняя запись (сортировка по pk desc)
User.first(5)                     # массив из 5
User.last(5)                      # массив из 5 (порядок сохранён)
User.find(42)                     # nil если не найдено
User.find!(42)                    # raises RecordNotFound если не найдено
User.find_by(email: "a@b.com")   # nil если не найдено
User.find_by!(email: "a@b.com")  # raises RecordNotFound если не найдено
User.none                         # пустой relation, HTTP-запрос не выполняется
```

## Агрегаты

### Подсчёт строк

```ruby
User.count                        # точный COUNT(*) — по умолчанию
User.any?
User.none?
User.one?
User.many?
User.exists?
User.where(active: true).count
```

`count` принимает необязательный режим, определяющий как PostgREST вычисляет итог:

```ruby
User.count              # :exact     — реальный COUNT(*), всегда точный
User.count(:planned)    # :planned   — оценка планировщика запросов (EXPLAIN)
User.count(:estimated)  # :estimated — из pg_class.reltuples, мгновенно
```

| Режим | SQL-эквивалент | Скорость | Точность |
|---|---|---|---|
| `:exact` | `COUNT(*)` | медленно на больших таблицах | точный |
| `:planned` | `EXPLAIN SELECT …` | быстро | приблизительный, учитывает фильтры |
| `:estimated` | `pg_class.reltuples` | мгновенно | приблизительный, игнорирует фильтры |

`:planned` и `:estimated` возвращают приближённые значения — PostgREST сигнализирует об этом префиксом `~` в заголовке `Content-Range` (`0-24/~1050`), который библиотека отбрасывает автоматически.

Используйте `:exact` (по умолчанию) когда число должно быть точным. Используйте `:planned` для пагинации, где достаточно приблизительной оценки. Используйте `:estimated` для счётчиков на дашборде с таблицами из миллионов строк.

`any?`, `none?`, `one?`, `many?` всегда используют `:exact`.

### Агрегаты по столбцам

Возвращают скалярное значение (строку, как возвращает PostgREST JSON). При необходимости приведите тип явно.

```ruby
User.average(:age)                # => "32.4"
User.sum(:score)                  # => "15000"
User.minimum(:age)                # => "18"
User.maximum(:age)                # => "75"

# Фильтры учитываются
User.where(active: true).average(:age)
User.joins(:companies).where(companies: { name: "Acme" }).maximum(:score)
```

> **Требуется настройка PostgREST:** агрегаты по столбцам используют API агрегатов PostgREST,
> который **отключён по умолчанию**. Добавьте в `postgrest.conf`:
>
> ```
> db-aggregates-enabled = true
> ```
>
> Без этого PostgREST вернёт ошибку при агрегатных запросах.

## Pluck / pick

```ruby
User.pluck(:id)                   # [1, 2, 3, ...]
User.pluck(:id, :name)            # [[1, "Alice"], [2, "Bob"], ...]
User.pick(:email)                 # "alice@example.com" (первое совпадение)
```

## Мутации

### Создание

```ruby
# Возвращает persisted-экземпляр (или nil если ответ пустой)
User.create(name: "Alice", email: "alice@example.com")

# Вызывает исключение при ошибке: UnprocessableEntity при нарушении ограничений (422),
# RecordNotSaved если PostgREST вернул пустое тело
User.create!(name: "Alice")

# Массовая вставка — возвращает массив persisted-записей
User.insert_all([{ name: "Alice" }, { name: "Bob" }])
```

`insert` — низкоуровневый аналог `create` с тем же HTTP-запросом и тем же значением возврата. Используйте `create` / `create!` для паттерна в стиле ActiveRecord.

### Upsert

```ruby
# Одиночный upsert — использует resolution=merge-duplicates в PostgREST
User.upsert(id: 1, name: "Alice Updated")

# Массовый upsert
User.upsert_all([
  { id: 1, name: "Alice Updated" },
  { id: 2, name: "Bob New" }
])
```

### Обновление

```ruby
# Массовое — обновляет все совпадающие строки, возвращает обновлённые записи
User.where(active: false).update_all(status: "archived")
User.where(role: "trial").update_all(expires_at: 30.days.from_now)

# Через экземпляр
user = User.find!(1)
user.update(name: "New Name")   # обновляет атрибуты и сохраняет
user.name = "Other"
user.save                        # возвращает true/false
```

### Удаление

```ruby
# Массовое — удаляет все совпадающие строки, возвращает удалённые записи
User.where(created_at: ..1.year.ago).delete_all
User.where(active: false).delete_all

# Через экземпляр
user.destroy          # DELETE по первичному ключу; запись помечается как destroyed
user.destroyed?       # => true
user.persisted?       # => false
user.save             # => false (destroyed-записи нельзя переставить через save)
```

### Reload

```ruby
user = User.find!(1)
user.name = "Локальное изменение"
user.reload   # повторно загружает из БД, отбрасывает локальные изменения
```

### Состояние персистентности

```ruby
User.new(name: "Alice").new_record?   # => true
User.find!(1).persisted?              # => true

user = User.new(name: "Alice")
user.save          # вставляет, помечает как persisted
user.persisted?    # => true

user.destroy
user.destroyed?    # => true
user.new_record?   # => false
```

### Особенности write-пути

**Ассоциации исключаются из сохранения.** `save` и `update` отправляют в PostgREST только скалярные (не Hash, не Array) атрибуты. Вложенные данные ассоциаций, загруженные через `with_*`, автоматически исключаются из тела PATCH — PostgREST отклонит запрос с 400, если в теле окажутся не-колонки.

**Токен/контекст клиента сохраняется в записи.** Записи, полученные из запроса, запоминают клиент, через который они были загружены. Методы экземпляра `save`, `update`, `destroy` и `reload` переиспользуют этот же клиент — RLS-политики, действовавшие при чтении, будут также применяться при записи.

```ruby
# И GET, и PATCH выполняются под user_jwt
user = User.with_token(user_jwt).find!(1)
user.update(name: "Новое имя")   # использует user_jwt, а не дефолтное соединение класса
```

**`save` возвращает false при 0 обновлённых строк.** Если PostgREST вернул пустой ответ после PATCH (например, строка не видна под RLS после записи), `save` вернёт `false`, даже если запись могла быть зафиксирована. Используйте `create!` или дополнительный `find!` после save, если нужны строгие гарантии.

**`create` / `create!` доступны на relation.** Можно вызывать на любом relation, в том числе с per-request токеном:

```ruby
User.with_token(user_jwt).create!(name: "Alice")   # INSERT под user_jwt
```

## ActiveModel (опционально)

`active_postgrest` не зависит от ActiveModel. Подключите его явно, чтобы получить `valid?`, `errors` и поддержку form-хелперов Rails (`form_with`).

**Вне Rails** — подключите после гема:

```ruby
require 'active_postgrest'
require 'active_postgrest/active_model'
```

**В Rails** — подключите railtie (например, в инициализаторе):

```ruby
require 'active_postgrest/railtie'
```

Добавьте `gem "activemodel"` в Gemfile, если он ещё не подтянут Rails.

После подключения:

```ruby
class User < ActivePostgrest::Base
  validates :name, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
end

user = User.new(email: "bad")
user.valid?           # => false
user.errors[:name]    # => ["can't be blank"]
user.save             # => false — валидация не прошла, HTTP-запрос не отправлен

user = User.new(name: "Alice", email: "alice@example.com")
user.save             # => true — сначала валидирует, потом POST
```

`form_with(model: @user)` работает, потому что `Base` получает `ActiveModel::Naming` и `ActiveModel::Conversion`.

## Ассоциации

Ассоциации оборачивают встроенный JSON из PostgREST — они **не** инициируют дополнительных HTTP-запросов.

```ruby
class User < ActivePostgrest::Base
  belongs_to :company
  belongs_to :mother, class_name: "User", foreign_key: :mother_id
  has_many   :posts
  has_one    :profile
end
```

Каждое объявление ассоциации определяет метод класса `with_*` для предварительной загрузки:

```ruby
User.with_company                        # джойн companies
User.with_company(fields: [:id, :name])  # джойн companies, выбрать id,name
User.with_posts
User.with_mother                         # псевдоним для самореферентного джойна
```

Данные должны быть встроены в ответ — сначала вызовите `with_*`, `joins` или `embed`:

```ruby
user = User.with_company.find!(1)
user.company.name   # работает — данные компании были встроены
```

## Приведение типов атрибутов

Объявите типы атрибутов для автоматического приведения строковых значений, возвращаемых PostgREST:

| Тип | Ruby-класс |
|-----|------------|
| `:date`     | `Date`       |
| `:datetime` | `Time`       |
| `:time`     | `Time`       |
| `:decimal`  | `BigDecimal` |
| `:integer`  | `Integer`    |

Необъявленные атрибуты передаются как есть (обычно `String`, `Integer`, `nil`).

Генератор автоматически маппит PostgreSQL-форматы на типы через `POSTGRES_TYPE_CAST`:

| PostgreSQL формат | Тип |
|---|---|
| `date` | `:date` |
| `timestamp`, `timestamp with/without time zone` | `:datetime` |
| `time`, `time with/without time zone` | `:time` |
| `numeric`, `decimal`, `real`, `double precision` | `:decimal` |

## Интроспекция схемы

```ruby
# Через объект соединения
User.connection.tables          # ["users", "companies", ...]
User.connection.table_schema("users")  # хэш с raw OpenAPI-определением

# Через модель
User.schema                     # хэш с raw определением
User.attributes                 # { "id" => "integer", "name" => "text", ... }
```

## Отладка

```ruby
User.where(active: true).limit(10).to_url
# => "http://localhost:3000/users?active=is.true&limit=10"

User.joins(:companies).where(active: true).to_sql
# => "SELECT *, companies!inner(*)\nFROM users\nWHERE active IS TRUE"
# Восстановлено из состояния relation — HTTP-запрос не выполняется.

User.where(active: true).explain
# Возвращает план выполнения PostgREST (требует PostgREST ≥ 10)
```

## Ошибки

| Класс | HTTP | Когда возникает |
|---|---|---|
| `ActivePostgrest::RecordNotFound`      | —    | `find!` или `find_by!` не нашли записей |
| `ActivePostgrest::BadRequest`          | 400  | Некорректный запрос или фильтр |
| `ActivePostgrest::Unauthorized`        | 401  | Отсутствует или недействительный JWT токен |
| `ActivePostgrest::Forbidden`           | 403  | Роль не имеет прав (RLS / GRANT) |
| `ActivePostgrest::ResourceNotFound`    | 404  | Таблица или схема не найдена |
| `ActivePostgrest::Conflict`            | 409  | Нарушение ограничения уникальности |
| `ActivePostgrest::UnprocessableEntity` | 422  | Нарушение FK, NOT NULL, check-ограничения |
| `ActivePostgrest::ServerError`         | 5xx  | Внутренняя ошибка PostgREST или PostgreSQL |
| `KeyError`                             | —    | Переменная `POSTGREST_URL` не задана и URL не указан явно |
| `Faraday::Error` (и подклассы)         | —    | Сетевая ошибка |

Все подклассы `ActivePostgrest::Error` предоставляют `#http_status`, `#code`, `#details` и `#hint` из тела ответа PostgREST.

## Ограничения

- **Нет `distinct`** — PostgREST не предоставляет модификатор `DISTINCT`. Используйте представление (view) вместо него.
- **Нет `group` / `having`** — агрегатные SQL-клаузы не поддерживаются REST API PostgREST.
- **Нет ленивой загрузки ассоциаций** — ассоциации работают только когда данные встроены в ответ через `joins` / `embed` / `with_*`. Автоматической подгрузки `user.company` нет.
- **`to_sql`** — восстанавливает приближённую SQL-строку из состояния relation без обращения к БД. Использует нотацию встраивания PostgREST (`companies!inner(*)`) вместо настоящих SQL JOIN, и показывает литеральные значения вместо плейсхолдеров `$1`. Используйте `explain` для реального плана выполнения.
- **`explain`** — требует PostgREST ≥ 10.
- **`count`** зависит от заголовка `Content-Range`. Если PostgREST настроен его подавлять, `count` вызывает `CountNotAvailable`. Режимы `:planned` и `:estimated` возвращают приближённые значения и работают быстрее, но не подходят там, где важна точность.

## Отличия от ActiveRecord

Библиотека намеренно повторяет API запросов ActiveRecord, но в ряде мест отличается — либо потому что PostgREST работает иначе, либо для предоставления специфичных для PostgREST возможностей.

### Как в ActiveRecord

```ruby
User.where(active: true)
User.where(age: { gt: 18 })
User.where(companies: { name: "Acme" })   # фильтр по джойну в стиле AR
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
User.where(a: 1).or(User.where(b: 2))       # AR-стиль OR
```

### Отличается от ActiveRecord

**Условия OR / AND** — `.or` работает так же, как в AR. `or_where` и `and_where` — специфичные для PostgREST хелперы с массивом условий:

```ruby
# Так же, как в AR — цепочки where + or
User.where(active: true).or(User.where(role: "admin"))
User.where(active: true).where(age: { gt: 18 }).or(User.where(role: "admin"))

# Специфично для PostgREST — массив условий
User.or_where([{ age: 18 }, { role: "admin" }])
User.and_where([{ age: { gt: 18 } }, { active: true }])
```

**Размещение NULL при сортировке** — AR требует сырого SQL, здесь keyword:

```ruby
# AR
User.order(Arel.sql("name ASC NULLS LAST"))

# active_postgrest
User.order(:name, :asc, nulls: :last)
```

**Regex-фильтры** — AR требует сырого SQL, здесь hash-оператор:

```ruby
# AR
User.where("name ~ ?", "^A")

# active_postgrest
User.where(name: { match: "^A" })
User.where(name: { imatch: "^a" })   # без учёта регистра
```

**Тип возврата агрегатов по столбцам** — AR's `average` возвращает `BigDecimal`, `sum`/`minimum`/`maximum` возвращают Ruby-тип столбца. Здесь все четыре возвращают `String` (JSON-значение PostgREST), при необходимости приведите тип явно:

```ruby
User.average(:age).to_f     # => 32.4
User.sum(:score).to_i       # => 15000
```

**`to_sql`** — AR возвращает реальный SQL, отправляемый в БД. Здесь восстанавливает приближённое представление из состояния relation без обращения к БД, но использует нотацию встраивания PostgREST вместо настоящих SQL JOIN:

```ruby
User.joins(:companies).where(active: true).to_sql
# => "SELECT *, companies!inner(*)\nFROM users\nWHERE active IS TRUE"
```

Используйте `explain` для реального плана выполнения.

### Специфично для PostgREST (нет аналога в AR)

```ruby
User.embed(:profile, fields: [:bio])              # встраивание вычисленной связи
User.joins(:companies, where: { active: true })   # фильтр на уровне джойна
User.where(active: true).to_url                   # просмотр сгенерированного URL
User.where(active: true).explain                  # план выполнения PostgREST
User.with_schema("analytics").where(active: true) # переключение схемы на запрос
User.count(:planned)                              # приближённый подсчёт от планировщика
User.count(:estimated)                            # мгновенный подсчёт из pg_class
User.spread(:companies)                           # развернуть столбцы связи в плоский объект
```

### Не реализовано

- **`distinct`** — не предоставляется REST API PostgREST. Используйте представление вместо него.
- **`group` / `having`** — не поддерживается REST API PostgREST.
- **Ленивая загрузка ассоциаций** — ассоциации работают только когда данные встроены в ответ через `joins` / `embed` / `with_*`. Автоматической подгрузки `user.company` нет.

## Благодарности

Библиотека спроектирована и создана с помощью [Claude](https://claude.ai) (Anthropic). Архитектура, реализация и тесты разработаны в рамках совместного рабочего процесса человек–ИИ с использованием [Claude Code](https://claude.ai/code).
