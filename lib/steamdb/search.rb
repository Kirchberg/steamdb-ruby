# frozen_string_literal: true

require 'uri'

module SteamDB
  module Search
    SEARCH_PATH = '/search/'.freeze

    module_function

    def games(query, region: 'us', limit: nil)
      raise ArgumentError, 'query must be present' if query.nil? || query.strip.empty?

      encoded_query = URI.encode_www_form_component(query.strip)
      document = SteamDB.fetch_page("#{SEARCH_PATH}?a=app&q=#{encoded_query}", region: region)

      results = extract_table(document).map do |row|
        parse_row(row)
      end.compact

      limit ? results.first(limit) : results
    end

    def extract_table(document)
      table = document.css('table').find do |node|
        header_text = node.at_css('thead')&.text&.downcase || ''
        header_text.include?('appid') || header_text.include?('app id')
      end

      return [] unless table

      table.css('tbody tr')
    end
    private_class_method :extract_table

    def parse_row(row)
      link = row.at_css('a[href*="/app/"]')
      return nil unless link

      app_id = link['href'].to_s.split('/').reject(&:empty?).last
      info_cells = row.css('td')

      {
        app_id: app_id&.to_i,
        name: link.text.strip,
        type: infer_type(info_cells),
        release_date: find_date(info_cells),
        price: info_cells[3]&.text&.strip,
        url: URI.join(SteamDB::BASE_URL, link['href']).to_s
      }
    end
    private_class_method :parse_row

    def infer_type(cells)
      raw = cells[0]&.text&.strip
      return raw unless raw.to_s.empty?

      cells[1]&.text&.strip
    end
    private_class_method :infer_type

    def find_date(cells)
      candidates = cells.select { |cell| cell['data-sort']&.match?(/\A\d+\z/) }
      timestamp_cell = candidates.min_by { |cell| cell['data-sort'].to_i }
      return nil unless timestamp_cell

      Integer(timestamp_cell['data-sort'])
    rescue ArgumentError, TypeError
      nil
    end
    private_class_method :find_date
  end
end
