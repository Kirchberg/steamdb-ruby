# frozen_string_literal: true

require 'json'
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
      Thread.current[:steamdb_client] || @client ||= HttpClient.new
    end

    def configure(client = self.client)
      yield(client)
    end

    def with_client(client)
      previous = Thread.current[:steamdb_client]
      Thread.current[:steamdb_client] = client
      yield(client)
    ensure
      Thread.current[:steamdb_client] = previous
    end
  end

  def self.fetch_page(path, region:, headers: {}, client: self.client)
    response = client.fetch(URI.join(BASE_URL, path), headers: headers, region: region)

    unless response.success?
      raise HTTPError, "Request failed with status #{response.status}"
    end

    Nokogiri::HTML(response.body)
  end

  def self.fetch_json(path, region:, headers: {}, client: self.client)
    response = client.fetch(URI.join(BASE_URL, path), headers: headers, region: region)

    unless response.success?
      raise HTTPError, "Request failed with status #{response.status}"
    end

    JSON.parse(extract_json_payload(response.body), symbolize_names: true)
  rescue JSON::ParserError => e
    raise HTTPError, "Failed to parse JSON from #{path}: #{e.message}"
  end

  def self.search_games(query, region: 'us', limit: nil, client: self.client)
    Search.games(query, region: region, limit: limit, client: client)
  end

  def self.trending(region: 'us', max_items: 10, client: self.client)
    Dashboard.trending(region: region, max_items: max_items, client: client)
  end

  def self.extract_json_payload(body)
    return '' if body.nil?

    match = body.match(/<pre>(.*)<\/pre>/m)
    match ? match[1] : body.to_s
  end
  private_class_method :extract_json_payload
end

require_relative 'steamdb/game'
require_relative 'steamdb/game_info'
require_relative 'steamdb/game_charts'
require_relative 'steamdb/depot'
require_relative 'steamdb/search'
require_relative 'steamdb/dashboard'
