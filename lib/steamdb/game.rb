# frozen_string_literal: true

require 'time'

module SteamDB
  class Game
    attr_reader :data

    def initialize(game_id, region: 'us')
      @game_id = game_id.to_s
      @region = region.to_s
      @page = nil
      @data = {
        info: {},
        prices: [],
        screenshots: []
      }
    end

    def fetch_data
      @page = SteamDB.fetch_page("/app/#{@game_id}/", region: @region)
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
      game_info[:library_logo_url] = parse_library_logo(page)
      game_info[:library_hero_url] = parse_library_hero(page)

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

    def parse_library_logo(page)
      # Find library_logo section in the assets table
      library_logo_url = nil
      library_logo_2x_url = nil
      
      page.css('tr').each do |row|
        cells = row.css('td')
        cells.each_with_index do |cell, i|
          if cell.text.strip == 'library_logo ↴'
            # Look for image/english and image2x/english in following rows
            rows = row.parent.css('tr')
            current_index = rows.index(row)
            
            # Check next 15 rows after library_logo ↴
            (current_index + 1..[current_index + 15, rows.length - 1].min).each do |idx|
              next_row_cells = rows[idx].css('td')
              
              next_row_cells.each_with_index do |nc, j|
                text = nc.text.strip
                
                if text == 'image/english' || text == 'image2x/english'
                  # Get the link in the next cell
                  link = next_row_cells[j + 1]&.at_css('a')
                  if link
                    href = link['href']
                    # Check if it's a logo file (logo.png, logo_2x.png, or contains "logo" in path)
                    if href.match?(/logo/i) || href.match?(/library_logo/i)
                      if text == 'image2x/english'
                        library_logo_2x_url = href
                      elsif text == 'image/english' && library_logo_url.nil?
                        library_logo_url = href
                      end
                    end
                  end
                end
              end
            end
            
            # Prefer 2x version if available, otherwise use 1x
            return library_logo_2x_url || library_logo_url
          end
        end
      end
      
      nil
    end

    def parse_library_hero(page)
      # Find library_hero section in the assets table
      library_hero_url = nil
      library_hero_2x_url = nil
      
      page.css('tr').each do |row|
        cells = row.css('td')
        cells.each_with_index do |cell, i|
          if cell.text.strip == 'library_hero ↴'
            # Look for image/english and image2x/english in following rows
            rows = row.parent.css('tr')
            current_index = rows.index(row)
            
            # Check next 15 rows after library_hero ↴
            (current_index + 1..[current_index + 15, rows.length - 1].min).each do |idx|
              next_row_cells = rows[idx].css('td')
              
              next_row_cells.each_with_index do |nc, j|
                text = nc.text.strip
                
                if text == 'image/english' || text == 'image2x/english'
                  # Get the link in the next cell
                  link = next_row_cells[j + 1]&.at_css('a')
                  if link
                    href = link['href']
                    # Check if it's a hero file (hero.png, hero_2x.png, or contains "hero" in path)
                    if href.match?(/hero/i) || href.match?(/library_hero/i)
                      if text == 'image2x/english'
                        library_hero_2x_url = href
                      elsif text == 'image/english' && library_hero_url.nil?
                        library_hero_url = href
                      end
                    end
                  end
                end
              end
            end
            
            # Prefer 2x version if available, otherwise use 1x
            return library_hero_2x_url || library_hero_url
          end
        end
      end
      
      nil
    end
  end
end
