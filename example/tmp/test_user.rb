# frozen_string_literal: true

u = User.with_parents.where(mother_id: 4).first
puts u.full_name
puts "Mother: #{u.mother&.full_name || 'nil'}"
puts "Father: #{u.father&.full_name || 'nil'}"
puts "Age: #{u.age}"
puts "Female: #{u.female?}"

puts "\n--- All users count ---"
puts User.all.count

puts "\n--- Users with parents ---"
User.with_parents.limit(3).each do |user|
  m = user.mother&.full_name || "-"
  f = user.father&.full_name || "-"
  puts "#{user.full_name} | mother: #{m} | father: #{f}"
end
