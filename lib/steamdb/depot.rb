# frozen_string_literal: true

require 'time'

module SteamDB
  class Depot
    attr_reader :data

    def initialize(depot_id, region: 'us')
      @depot_id = depot_id.to_s
      @region = region.to_s
      @page = nil
      @data = {
        info: {}
      }
    end

    def fetch_data
      @page = SteamDB.fetch_page("/depot/#{@depot_id}/", region: @region)
      self
    rescue HTTPError => e
      raise Error, "Unable to fetch depot #{@depot_id}: #{e.message}"
    end

    def parse
      raise Error, 'Call #fetch_data before #parse' unless @page

      info = parse_depot_information(@page)
      @data = { info: info }
    end

    def info
      @data[:info]
    end

    def build_id
      info[:build_id]
    end

    def manifest_id
      info[:manifest_id]
    end

    def size
      info[:size]
    end

    def download_size
      info[:download_size]
    end

    private

    def parse_depot_information(page)
      depot_info = {}

      page.css('.table-hover > tbody > tr').each do |row|
        cells = row.css('td')
        label = text_content(cells[0])

        case label
        when 'Depot ID'
          depot_info[:id] = text_content(cells[1]).to_i
        when 'Build ID'
          depot_info[:build_id] = text_content(cells[1]).to_i
        when 'Manifest ID'
          depot_info[:manifest_id] = text_content(cells[1]).to_i
        when 'Creation date'
          depot_info[:creation_date] = parse_date_range(text_content(cells[1]))
        when 'Last update'
          depot_info[:last_update] = parse_date_range(text_content(cells[1]))
        when 'Size on disk'
          depot_info[:size] = text_content(cells[1])
        when 'Download size'
          depot_info[:download_size] = normalize_download_size(cells[1])
        end
      end

      depot_info
    end

    def parse_date_range(value)
      cleaned = value.to_s.gsub('()', ' ').strip
      parts = cleaned.split(' – ')
      return nil if parts.empty?

      Time.parse(parts.join(' ')).utc.to_i * 1000
    rescue ArgumentError
      nil
    end

    def normalize_download_size(node)
      return nil unless node

      node.text.lines.map(&:strip).reject(&:empty?).last
    end

    def text_content(node)
      node&.text&.strip.to_s
    end
  end
end
