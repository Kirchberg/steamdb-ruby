# frozen_string_literal: true

require 'bundler/setup'
require 'nokogiri'
require_relative '../lib/steamdb'

module FixtureHelper
  def fixture_path(name)
    File.expand_path("fixtures/#{name}", __dir__)
  end

  def load_fixture(name)
    File.read(fixture_path(name))
  end
end

RSpec.configure do |config|
  config.include FixtureHelper
  config.disable_monkey_patching!
  config.order = :random
end
