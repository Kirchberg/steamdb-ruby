# frozen_string_literal: true

require_relative 'table_helper'
require_relative 'igdb_link'

module SteamDB
  module ChartsOverview
    module_function

    MOST_PLAYED_TITLES = ['Most played games', 'Steam Charts'].freeze
    MOST_PLAYED_HEADERS = ['current', '24h peak', 'all time peak'].freeze

    def most_played(region: 'us', max_items: 10, include_igdb: false, client: SteamDB.client)
      document = SteamDB.fetch_page('/charts/', region: region, client: client)
      table = TableHelper.find_table(document, titles: MOST_PLAYED_TITLES, headers: MOST_PLAYED_HEADERS)
      table ||= TableHelper.find_table(document, headers: MOST_PLAYED_HEADERS)
      return [] unless table

      entries = parse_most_played(table, max_items)
      return entries unless include_igdb

      entries.each do |entry|
        entry[:igdb_url] = IgdbLink.fetch(entry[:app_id], region: region, client: client)
      end
      entries
    end

    def parse_most_played(table, max_items)
      header_map = TableHelper.header_index_map(table)

      rank_idx = TableHelper.header_index(header_map, ['#', 'rank'])
      name_idx = TableHelper.header_index(header_map, ['name'])
      current_idx = TableHelper.header_index(header_map, ['current'])
      peak_24h_idx = TableHelper.header_index(header_map, ['24h peak', '24h'])
      peak_all_idx = TableHelper.header_index(header_map, ['all time peak', 'all-time peak', 'all time'])

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
          current_players: TableHelper.extract_number(cells[current_idx]),
          peak_24h: TableHelper.extract_number(cells[peak_24h_idx]),
          peak_all_time: TableHelper.extract_number(cells[peak_all_idx]),
          url: TableHelper.absolute_url(link['href']),
          store_url: TableHelper.store_url(app_id)
        }
      end.compact

      max_items ? rows.first(max_items) : rows
    end
    private_class_method :parse_most_played
  end
end
