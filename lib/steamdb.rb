# frozen_string_literal: true

require 'net/http'
require 'nokogiri'
require 'uri'

require_relative 'steamdb/version'
require_relative 'steamdb/http_client'
require_relative 'steamdb/captcha_detector'
require_relative 'steamdb/flaresolverr'
require_relative 'steamdb/session'

module SteamDB
  class Error < StandardError; end
  class HTTPError < Error; end

  BASE_URL = 'https://steamdb.info'

  class << self
    attr_writer :client

    def client
      @client ||= HttpClient.new
    end

    def configure
      yield(client)
    end
  end

  def self.fetch_page(path, region:, headers: {})
    response = client.fetch(URI.join(BASE_URL, path), headers: headers, region: region)

    unless response.success?
      raise HTTPError, "Request failed with status #{response.status}"
    end

    Nokogiri::HTML(response.body)
  end
end

require_relative 'steamdb/game'
require_relative 'steamdb/depot'
require_relative 'steamdb/search'
require_relative 'steamdb/dashboard'

module SteamDB
  def self.search_games(query, region: 'us', limit: nil)
    Search.games(query, region: region, limit: limit)
  end

  def self.trending(region: 'us', max_items: 10)
    Dashboard.trending(region: region, max_items: max_items)
  end
end
