# frozen_string_literal: true

require 'time'

module SteamDB
  class Game
    attr_reader :data

    def initialize(game_id, region: 'us', client: SteamDB.client)
      @game_id = game_id.to_s
      @region = region.to_s
      @client = client
      @page = nil
      @data = {
        info: {},
        prices: [],
        screenshots: []
      }
    end

    def fetch_data
      @page = SteamDB.fetch_page("/app/#{@game_id}/", region: @region, client: @client)
      self
    rescue HTTPError => e
      raise Error, "Unable to fetch game #{@game_id}: #{e.message}"
    end

    def parse
      raise Error, 'Call #fetch_data before #parse' unless @page

      info = parse_game_information(@page)
      prices = parse_prices(@page)
      screenshots = parse_screenshots(@page)

      @data = {
        info: info,
        prices: prices,
        screenshots: screenshots
      }
    end

    def prices
      @data[:prices]
    end

    def screenshots
      @data[:screenshots]
    end

    def name
      @data.dig(:info, :name)
    end

    def description
      @data.dig(:info, :description)
    end

    def logo_url
      @data.dig(:info, :logo_url)
    end

    def library_logo_url
      @data.dig(:info, :library_logo_url)
    end

    def library_hero_url
      @data.dig(:info, :library_hero_url)
    end

    def metacritic_score
      @data.dig(:info, :metacritic_score)
    end

    def metacritic_fullurl
      @data.dig(:info, :metacritic_fullurl)
    end

    def metacritic_name
      @data.dig(:info, :metacritic_name)
    end

    def info
      @data[:info]
    end

    private

    def parse_game_information(page)
      game_info = {}

      info_table = find_info_table(page)
      if info_table
        info_table.css('tr').each do |row|
          cells = row.css('td, th')
          next if cells.length < 2

          heading = text_content(cells[0])
          value_cell = cells[1]

          case heading
          when 'App ID'
            game_info[:id] = text_content(value_cell).to_i
          when 'App Type'
            game_info[:type] = text_content(value_cell)
          when 'Developer'
            game_info[:developer] = text_content(value_cell)
          when 'Publisher'
            game_info[:publisher] = text_content(value_cell)
          when 'Last Record Update'
            timestamp = value_cell&.at_css('span')&.[]('title')
            game_info[:last_update] = parse_timestamp(timestamp)
          when 'Name'
            game_info[:name] = text_content(value_cell)
          when 'Release Date'
            timestamp = value_cell&.at_css('span')&.[]('title')
            game_info[:release_date] = parse_timestamp(timestamp)
          when 'Supported Systems'
            systems = value_cell&.at_css('meta')&.[]('content') || text_content(value_cell)
            game_info[:os] = systems.to_s.split(', ').reject(&:empty?)
          end
        end
      end

      # Parse additional metadata table (contains Metacritic data)
      page.css('table tr').each do |row|
        cells = row.css('td')
        next if cells.length < 2

        heading = text_content(cells[0])

        case heading
        when 'metacritic_score'
          score_text = text_content(cells[1])
          game_info[:metacritic_score] = score_text.to_i if score_text.match?(/^\d+$/)
        when 'metacritic_fullurl'
          link = cells[1]&.at_css('a')
          game_info[:metacritic_fullurl] = link['href'] if link && link['href']
        when 'metacritic_name'
          game_info[:metacritic_name] = text_content(cells[1])
        end
      end

      if game_info[:name].nil? || game_info[:name].empty?
        game_info[:name] = text_content(page.at_css('h1'))
      end

      game_info[:description] = page.at_css('p.header-description')&.text&.strip.to_s
      game_info[:logo_url] = page.at_css('img.app-logo')&.[]('src')
      assets = parse_library_assets(page)
      game_info[:library_logo_url] = assets[:library_logo_url]
      game_info[:library_hero_url] = assets[:library_hero_url]

      game_info
    end

    def find_info_table(page)
      page.css('table').find do |table|
        table.css('tr').any? do |row|
          text_content(row.css('td, th')[0]) == 'App ID'
        end
      end
    end

    def parse_prices(page)
      page.css('.table-prices > tbody > tr').map do |row|
        cells = row.css('td')
        region_cell = cells[0]

        {
          country_code: region_cell&.[]('data-cc'),
          currency: squish_text(region_cell&.text),
          price: squish_text(cells[1]&.text),
          converted_price: squish_text(cells[2]&.text)
        }
      end
    end

    def parse_screenshots(page)
      page.css('div#screenshots a').map { |node| node['href'] }.compact
    end

    def parse_timestamp(value)
      return nil if value.nil? || value.empty?

      Time.parse(value).utc.to_i * 1000
    rescue ArgumentError
      nil
    end

    def text_content(node)
      node&.text&.strip.to_s
    end

    def squish_text(text)
      text.to_s.gsub(/\s+/, ' ').strip
    end

    def parse_library_assets(page)
      rows = page.css('tr')
      assets_1x = {}
      assets_2x = {}

      rows.each_with_index do |row, row_index|
        label = row.at_css('td')&.text&.strip
        next unless label == 'library_logo ↴' || label == 'library_hero ↴'

        key = label.include?('logo') ? :library_logo_url : :library_hero_url
        scan_rows = rows[(row_index + 1)..(row_index + 15)] || []

        scan_rows.each do |next_row|
          cells = next_row.css('td')
          next if cells.empty?

          format = cells[0]&.text&.strip
          next unless format == 'image/english' || format == 'image2x/english'

          href = cells[1]&.at_css('a')&.[]('href')
          next unless href

          if key == :library_logo_url
            next unless href.match?(/logo/i) || href.match?(/library_logo/i)
          else
            next unless href.match?(/hero/i) || href.match?(/library_hero/i)
          end

          if format == 'image2x/english'
            assets_2x[key] ||= href
          else
            assets_1x[key] ||= href
          end
        end
      end

      {
        library_logo_url: assets_2x[:library_logo_url] || assets_1x[:library_logo_url],
        library_hero_url: assets_2x[:library_hero_url] || assets_1x[:library_hero_url]
      }
    end
  end
end
