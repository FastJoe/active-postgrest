require_relative "lib/active_postgrest/version"

Gem::Specification.new do |s|
  s.name        = "active_postgrest"
  s.version     = ActivePostgrest::VERSION
  s.summary     = "ActiveRecord-style Ruby client for PostgREST"
  s.description = "Query PostgREST APIs using a familiar ActiveRecord-like interface"
  s.authors     = ["Evgeny Sokolov"]
  s.email       = ["evgeny.sokolov@gmail.com"]
  s.homepage    = "https://github.com/FastJoe/active-postgrest"
  s.license     = "Apache-2.0"
  s.required_ruby_version = ">= 3.0"
  s.files       = Dir["lib/**/*"] + ["LICENSE"]
  s.require_paths = ["lib"]
  s.metadata = {
    "source_code_uri" => "https://github.com/FastJoe/active-postgrest",
    "changelog_uri"   => "https://github.com/FastJoe/active-postgrest/blob/main/CHANGELOG.md"
  }

  s.add_dependency "faraday", ">= 2.0"
  s.add_dependency "faraday-net_http", ">= 2.0"
  s.add_dependency "activesupport", ">= 7.0"

  s.add_development_dependency "rspec", "~> 3.0"
  s.add_development_dependency "rubocop", "~> 1.0"
end
