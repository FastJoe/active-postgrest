require_relative "lib/active_postgrest/version"

Gem::Specification.new do |s|
  s.name        = "active_postgrest"
  s.version     = ActivePostgrest::VERSION
  s.summary     = "ActiveRecord-style Ruby ORM for PostgREST"
  s.description = "ActiveRecord-style ORM for PostgREST: queries, CRUD operations, associations, scopes, and ActiveModel integration"
  s.authors     = ["Evgeny Sokolov"]
  s.email       = ["evgeny.sokolov@gmail.com"]
  s.homepage    = "https://github.com/FastJoe/active-postgrest"
  s.license     = "Apache-2.0"
  s.required_ruby_version = ">= 3.2"
  s.signing_key = File.expand_path("~/.gem/gem-private_key.pem") if File.exist?(File.expand_path("~/.gem/gem-private_key.pem"))
  s.cert_chain  = ["certs/gem-public_cert.pem"]
  s.files       = Dir["lib/**/*"] + ["LICENSE", "certs/gem-public_cert.pem"]
  s.require_paths = ["lib"]
  s.metadata = {
    "source_code_uri"       => "https://github.com/FastJoe/active-postgrest",
    "changelog_uri"         => "https://github.com/FastJoe/active-postgrest/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  s.add_dependency "faraday", ">= 2.0"
  s.add_dependency "faraday-net_http", ">= 2.0"
  s.add_dependency "activesupport", ">= 7.0"

  s.add_development_dependency "rspec", "~> 3.0"
  s.add_development_dependency "simplecov", "~> 0.22"
  s.add_development_dependency "rubocop", "~> 1.0"
  s.add_development_dependency "rubocop-rspec", "~> 3.0"
  s.add_development_dependency "bundler-audit", "~> 0.9"
end
