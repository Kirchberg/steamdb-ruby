# frozen_string_literal: true

require 'uri'
require_relative 'table_helper'
require_relative 'igdb_link'

module SteamDB
  module Upcoming
    module_function

    UPCOMING_TITLES = [
      'Upcoming releases on Steam',
      'Releases on Steam for the past 7 days'
    ].freeze
    UPCOMING_HEADERS = ['name', 'release', 'follows'].freeze

    def upcoming(region: 'us', max_items: 10, include_igdb: false, lastweek: nil, min_rating: nil, sort: nil, client: SteamDB.client)
      path = build_path(lastweek: lastweek, min_rating: min_rating, sort: sort)
      document = SteamDB.fetch_page(path, region: region, client: client)
      table = TableHelper.find_table(document, titles: UPCOMING_TITLES, headers: UPCOMING_HEADERS)
      table ||= TableHelper.find_table(document, headers: UPCOMING_HEADERS)
      return [] unless table

      entries = parse_table(table, max_items)
      return entries unless include_igdb

      entries.each do |entry|
        entry[:igdb_url] = IgdbLink.fetch(entry[:app_id], region: region, client: client)
      end
      entries
    end

    def build_path(lastweek:, min_rating:, sort:)
      params = {}
      params['lastweek'] = lastweek == true ? '' : lastweek unless lastweek.nil?
      params['min_rating'] = min_rating unless min_rating.nil?
      params['sort'] = sort unless sort.nil?

      query = URI.encode_www_form(params)
      query.empty? ? '/upcoming/' : "/upcoming/?#{query}"
    end
    private_class_method :build_path

    def parse_table(table, max_items)
      header_map = TableHelper.header_index_map(table)

      name_idx = TableHelper.header_index(header_map, ['name'])
      percent_idx = TableHelper.header_index(header_map, ['%', 'percent'])
      price_idx = TableHelper.header_index(header_map, ['price'])
      rating_idx = TableHelper.header_index(header_map, ['rating'])
      release_idx = TableHelper.header_index(header_map, ['release'])
      follows_idx = TableHelper.header_index(header_map, ['follows', 'followers'])
      gain_idx = TableHelper.header_index(header_map, ['7d gain', 'gain'])
      online_idx = TableHelper.header_index(header_map, ['online'])
      peak_idx = TableHelper.header_index(header_map, ['peak'])

      rows = table.css('tbody tr').map.with_index do |row, idx|
        cells = row.css('td')
        app_id = row['data-appid']&.to_i
        link = row.at_css('a[href*="/app/"]')
        app_id ||= TableHelper.extract_app_id(link) if link

        name = TableHelper.extract_text(cells[name_idx])
        name = link.text.strip if (name.nil? || name.empty?) && link

        cell_at = ->(index) { index ? cells[index] : nil }

        {
          app_id: app_id,
          name: name,
          rank: idx + 1,
          percent: TableHelper.extract_number(cell_at.call(percent_idx)),
          percent_text: TableHelper.extract_text(cell_at.call(percent_idx)),
          price: TableHelper.extract_text(cell_at.call(price_idx)),
          rating: TableHelper.extract_text(cell_at.call(rating_idx)),
          release_date: TableHelper.extract_timestamp(cell_at.call(release_idx)),
          release_date_text: TableHelper.extract_text(cell_at.call(release_idx)),
          follows: TableHelper.extract_number(cell_at.call(follows_idx)),
          gain_7d: TableHelper.extract_number(cell_at.call(gain_idx)),
          online: TableHelper.extract_number(cell_at.call(online_idx)),
          peak: TableHelper.extract_number(cell_at.call(peak_idx)),
          url: app_id ? "#{SteamDB::BASE_URL}/app/#{app_id}/" : TableHelper.absolute_url(link&.[]('href')),
          store_url: TableHelper.store_url(app_id)
        }
      end.compact

      max_items ? rows.first(max_items) : rows
    end
    private_class_method :parse_table
  end
end
