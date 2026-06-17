require "faker"

Faker::Config.locale = "ru"

# Используем AR напрямую для сидов (не через PostgREST)
class SeedUser < ApplicationRecord
  self.table_name = "users"
end

puts "Удаляем старые данные..."
SeedUser.delete_all

MALE_MIDDLES   = %w[Александрович Михайлович Сергеевич Дмитриевич Андреевич Алексеевич Николаевич Иванович Владимирович Евгеньевич].freeze
FEMALE_MIDDLES = %w[Александровна Михайловна Сергеевна Дмитриевна Андреевна Алексеевна Николаевна Ивановна Владимировна Евгеньевна].freeze

puts "Создаём 100 пользователей..."
now = Time.current
users = 100.times.map do
  gender = %w[male female].sample
  middles = gender == "male" ? MALE_MIDDLES : FEMALE_MIDDLES
  {
    first_name:  gender == "male" ? Faker::Name.male_first_name : Faker::Name.female_first_name,
    last_name:   Faker::Name.last_name,
    middle_name: rand < 0.8 ? middles.sample : nil,
    birth_date:  Faker::Date.birthday(min_age: 18, max_age: 70),
    gender:      gender,
    mother_id:   nil,
    father_id:   nil,
    created_at:  now,
    updated_at:  now
  }
end

SeedUser.insert_all(users)

# Добавляем родителей ~30% пользователей
all     = SeedUser.all.to_a
mothers = all.select { _1.gender == "female" }.map(&:id)
fathers = all.select { _1.gender == "male" }.map(&:id)

all.sample(30).each do |user|
  updates = {}
  if mothers.size > 1
    pool = mothers.reject { _1 == user.id }
    updates[:mother_id] = pool.sample if rand < 0.7
  end
  if fathers.size > 1
    pool = fathers.reject { _1 == user.id }
    updates[:father_id] = pool.sample if rand < 0.7
  end
  SeedUser.where(id: user.id).update_all(updates) if updates.any?
end

with_parents = SeedUser.where.not(mother_id: nil).or(SeedUser.where.not(father_id: nil)).count
puts "Готово! Создано #{SeedUser.count} пользователей, из них #{with_parents} с родителями."
