class Company < ActivePostgrest::Base
  include CompanyAttributes

  has_many :users
end
