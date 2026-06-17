# frozen_string_literal: true

u = User.with_company.where(company_id: 2).first
puts "User: #{u.full_name}"
puts "Company: #{u.company.name} (INN: #{u.company.inn})"

puts "\n--- Company with users ---"
c = Company.with_users.where(id: 2).first
puts "#{c.name}: #{c["users"].size} users"
