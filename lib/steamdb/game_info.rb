# frozen_string_literal: true

require_relative 'game'

module SteamDB
  class GameInfo < Game
    def fetch_data
      @page = SteamDB.fetch_page("/app/#{@game_id}/info/", region: @region, client: @client)
      self
    rescue HTTPError => e
      raise Error, "Unable to fetch game info #{@game_id}: #{e.message}"
    end

    def parse
      super

      @data[:tags] = parse_tags(@page)
      @data[:languages] = parse_languages(@page)
      @data[:store_packages] = parse_table_by_heading(@page, 'Store Packages')
      @data[:packages] = parse_table_by_heading(@page, 'Packages')
      @data[:dlc] = parse_table_by_heading(@page, 'Downloadable Content')
      @data[:depots] = parse_table_by_heading(@page, 'Depots')

      @data
    end

    private

    def parse_tags(page)
      page.css('a[href^="/tag/"]').map { |node| node.text.strip }.reject(&:empty?).uniq
    end

    def parse_languages(page)
      table = page.at_css('table.table-languages')
      return [] unless table

      headers = table.css('thead th').map { |node| node.text.strip }
      rows = table.css('tbody tr').map do |row|
        cells = row.css('td').map { |node| node.text.strip }
        next if cells.empty?

        language = cells[0].to_s
        next if language.empty?

        data = { language: language }
        headers[1..].to_a.each_with_index do |header, idx|
          key = normalize_header(header)
          next if key.nil? || key.empty?

          value = cells[idx + 1].to_s
          data[key.to_sym] = value.casecmp?('yes')
        end

        data
      end

      rows.compact
    end

    def parse_table_by_heading(page, heading)
      table = table_after_heading(page, heading)
      return [] unless table

      parse_table(table)
    end

    def table_after_heading(page, heading)
      header = page.css('h2').find { |node| node.text.strip == heading }
      return nil unless header

      header.xpath('following::table').first
    end

    def parse_table(table)
      headers = table.css('thead th').map { |node| node.text.strip }

      table.css('tbody tr').map do |row|
        cells = row.css('td')
        next if cells.empty?

        values = cells.map { |cell| cell.text.strip }
        row_data = {}

        headers.each_with_index do |header, idx|
          key = normalize_header(header)
          next if key.nil? || key.empty?

          value = values[idx].to_s
          row_data[key.to_sym] = coerce_value(key, value)
        end

        row_data.empty? ? nil : row_data
      end.compact
    end

    def normalize_header(header)
      return nil if header.nil?

      key = header.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/\A_+|_+\z/, '')
      return nil if key.empty?

      case key
      when 'appid'
        'app_id'
      when 'subid'
        'sub_id'
      when 'dl'
        'download_size'
      else
        key
      end
    end

    def coerce_value(key, value)
      return nil if value.nil? || value.empty?

      if key.to_s.end_with?('id') && value.match?(/\A\d+\z/)
        value.to_i
      else
        value
      end
    end
  end
end
