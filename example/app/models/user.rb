class User < ActivePostgrest::Base
  include UserAttributes

  belongs_to :company
  belongs_to :mother, class_name: "User", foreign_key: :mother_id
  belongs_to :father, class_name: "User", foreign_key: :father_id

  def self.with_mother(fields: [])
    embed(:mother, fields: fields)
  end

  def self.with_father(fields: [])
    embed(:father, fields: fields)
  end

  def self.with_parents(fields: [])
    embed(:mother, fields: fields).embed(:father, fields: fields)
  end

  def full_name
    [last_name, first_name, middle_name].compact.join(" ")
  end

  def age
    return unless birth_date
    today = Date.today
    today.year - birth_date.year - (today.yday < birth_date.yday ? 1 : 0)
  end

  def male?   = gender == "male"
  def female? = gender == "female"
end