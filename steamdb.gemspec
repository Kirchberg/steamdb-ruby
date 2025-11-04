# frozen_string_literal: true

require_relative 'lib/steamdb/version'

Gem::Specification.new do |spec|
  spec.name          = 'steamdb'
  spec.version       = SteamDB::VERSION
  spec.authors       = ['Kirchberg']
  spec.email         = ['']

  spec.summary       = 'SteamDB scraper with Cloudflare bypass - Get game data as JSON'
  spec.description   = 'A Ruby gem for scraping SteamDB with automatic Cloudflare bypass. Get game data, prices, and screenshots in JSON format via CLI or Ruby API.'
  spec.homepage      = 'https://github.com/kirchberg/steamdb-ruby'
  spec.license       = 'MIT'

  spec.required_ruby_version = Gem::Requirement.new('>= 3.0')

  spec.metadata = {
    'homepage_uri' => spec.homepage,
    'source_code_uri' => spec.homepage,
    'changelog_uri' => "#{spec.homepage}#readme"
  }

  spec.files = Dir.glob('lib/**/*') + Dir.glob('bin/steamdb') + %w[LICENSE README.md]
  spec.require_paths = ['lib']
  spec.executables = ['steamdb']

  spec.add_dependency 'nokogiri', '>= 1.15'
  spec.add_dependency 'http-cookie', '>= 1.0'

  spec.add_development_dependency 'bundler', '>= 2.5'
  spec.add_development_dependency 'rake', '>= 13.0'

  # Optional dependencies for enhanced functionality
  # For browser automation and manual CAPTCHA solving:
  #   gem install playwright-ruby-client
  #   npx playwright install chromium
end
