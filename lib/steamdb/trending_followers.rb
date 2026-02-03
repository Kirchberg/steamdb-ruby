# frozen_string_literal: true

require_relative 'table_helper'
require_relative 'igdb_link'

module SteamDB
  module TrendingFollowers
    module_function

    TRENDING_TITLES = ['Trending Steam Games By Followers Gain'].freeze
    TRENDING_HEADERS = ['follows', '7d gain'].freeze

    def trending(region: 'us', max_items: 10, include_igdb: false, client: SteamDB.client)
      document = SteamDB.fetch_page('/stats/trendingfollowers/', region: region, client: client)
      table = TableHelper.find_table(document, titles: TRENDING_TITLES, headers: TRENDING_HEADERS)
      return [] unless table

      entries = parse_trending(table, max_items)
      return entries unless include_igdb

      entries.each do |entry|
        entry[:igdb_url] = IgdbLink.fetch(entry[:app_id], region: region, client: client)
      end
      entries
    end

    def parse_trending(table, max_items)
      header_map = TableHelper.header_index_map(table)

      rank_idx = TableHelper.header_index(header_map, ['#', 'rank'])
      name_idx = TableHelper.header_index(header_map, ['name'])
      percent_idx = TableHelper.header_index(header_map, ['%', 'percent'])
      price_idx = TableHelper.header_index(header_map, ['price'])
      rating_idx = TableHelper.header_index(header_map, ['rating'])
      release_idx = TableHelper.header_index(header_map, ['release'])
      follows_idx = TableHelper.header_index(header_map, ['follows', 'followers'])
      gain_idx = TableHelper.header_index(header_map, ['7d gain', '7d', 'gain'])

      rows = table.css('tbody tr').map do |row|
        cells = row.css('td')
        link = row.at_css('a[href*="/app/"]')
        next unless link

        app_id = TableHelper.extract_app_id(link)
        name = TableHelper.extract_text(cells[name_idx])
        name = link.text.strip if name.nil? || name.empty?

        {
          app_id: app_id,
          name: name,
          rank: TableHelper.extract_rank(row, cells, rank_idx),
          percent: TableHelper.extract_number(cells[percent_idx]),
          percent_text: TableHelper.extract_text(cells[percent_idx]),
          price: TableHelper.extract_text(cells[price_idx]),
          rating: TableHelper.extract_text(cells[rating_idx]),
          release_date: TableHelper.extract_timestamp(cells[release_idx]),
          release_date_text: TableHelper.extract_text(cells[release_idx]),
          follows: TableHelper.extract_number(cells[follows_idx]),
          gain_7d: TableHelper.extract_number(cells[gain_idx]),
          url: TableHelper.absolute_url(link['href']),
          store_url: TableHelper.store_url(app_id)
        }
      end.compact

      max_items ? rows.first(max_items) : rows
    end
    private_class_method :parse_trending
  end
end
