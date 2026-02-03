# frozen_string_literal: true

require 'uri'

module SteamDB
  module TableHelper
    module_function

    def normalize_header(text)
      normalized = text.to_s.downcase.strip
      return 'rank' if normalized == '#'

      normalized.gsub(/\s+/, ' ').gsub(/[^a-z0-9%]+/, ' ').strip
    end

    def normalize_title(text)
      text.to_s.downcase.strip.gsub(/\s+/, ' ')
    end

    def table_title(table)
      title = table.at_css('thead .table-title')&.text&.strip
      return title unless title.nil? || title.empty?

      heading = table.xpath('preceding::h1[1] | preceding::h2[1] | preceding::h3[1]').first
      heading&.text&.strip
    end

    def header_index_map(table)
      header_row = select_header_row(table)
      headers = header_row ? header_row.css('th').map { |th| normalize_header(th.text) } : []
      headers.each_with_index.with_object({}) do |(header, idx), map|
        next if header.nil? || header.empty?

        map[header] ||= idx
      end
    end

    def header_index(header_map, candidates)
      Array(candidates).each do |candidate|
        key = normalize_header(candidate)
        next if key.empty?

        idx = header_map[key]
        return idx unless idx.nil?
      end
      nil
    end

    def find_table(document, titles: nil, headers: nil)
      normalized_titles = Array(titles).map { |title| normalize_title(title) }.reject(&:empty?)
      normalized_headers = Array(headers).map { |header| normalize_header(header) }.reject(&:empty?)

      document.css('table').find do |table|
        title_ok = normalized_titles.empty? || title_matches?(table_title(table), normalized_titles)
        headers_ok = normalized_headers.empty? || headers_present?(header_index_map(table), normalized_headers)
        title_ok && headers_ok
      end
    end

    def extract_rank(row, cells, rank_idx)
      if row['data-position']
        Integer(row['data-position'])
      elsif rank_idx && cells[rank_idx]
        cell = cells[rank_idx]
        sort_value = cell['data-sort']
        return Integer(sort_value) if sort_value&.match?(/\A\d+\z/)

        digits = cell.text.to_s.gsub(/[^\d]/, '')
        return Integer(digits) unless digits.empty?
      end
    rescue ArgumentError, TypeError
      nil
    end

    def extract_number(cell)
      return nil unless cell

      value = parse_number(cell['data-sort'])
      return value unless value.nil?

      parse_number(cell.text)
    end

    def extract_text(cell)
      cell&.text&.strip
    end

    def extract_timestamp(cell)
      return nil unless cell

      sort_value = cell['data-sort']
      return nil unless sort_value && sort_value.match?(/\A\d+\z/)

      sort_value.to_i
    end

    def extract_app_id(link)
      href = link['href'].to_s
      match = href.match(%r{/app/(\d+)})
      return match[1].to_i if match

      href.split('/').reject(&:empty?).last&.to_i
    end

    def store_url(app_id)
      return nil unless app_id && app_id.to_i.positive?

      "https://store.steampowered.com/app/#{app_id}/"
    end

    def absolute_url(path)
      return nil if path.nil? || path.to_s.strip.empty?

      URI.join(SteamDB::BASE_URL, path.to_s).to_s
    rescue URI::InvalidURIError
      nil
    end

    def title_matches?(title, normalized_titles)
      return false if title.nil? || title.empty?

      normalized_title = normalize_title(title)
      normalized_titles.any? { |candidate| normalized_title.include?(candidate) }
    end
    private_class_method :title_matches?

    def headers_present?(header_map, normalized_headers)
      normalized_headers.all? { |header| header_map.key?(header) }
    end
    private_class_method :headers_present?

    def parse_number(value)
      return nil if value.nil?

      text = value.to_s.strip
      return nil if text.empty?

      cleaned = text.gsub(/[,+]/, '')
      cleaned = cleaned.gsub('%', '')
      cleaned = cleaned.gsub(/\A\+/, '')
      return nil unless cleaned.match?(/\A-?\d+(\.\d+)?\z/)

      cleaned.include?('.') ? cleaned.to_f : cleaned.to_i
    end
    private_class_method :parse_number

    def select_header_row(table)
      rows = table.css('thead tr')
      return nil if rows.empty?

      rows.max_by { |row| row.css('th').length }
    end
    private_class_method :select_header_row
  end
end
