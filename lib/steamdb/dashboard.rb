# frozen_string_literal: true

module SteamDB
  module Dashboard
    module_function

    def trending(region: 'us', max_items: 10, client: SteamDB.client)
      document = SteamDB.fetch_page('/', region: region, client: client)
      seen_titles = {}

      document.css('table').filter_map do |table|
        entries = parse_table(table, max_items)
        next if entries.empty?

        title = derive_title_for(table)
        next if title.nil? || title.empty?
        next if seen_titles[title]

        seen_titles[title] = true
        { title: title, entries: entries }
      end
    end

    def parse_table(table, max_items)
      table.css('tbody tr').map { |row| parse_row(row) }.compact.first(max_items)
    end
    private_class_method :parse_table

    def parse_row(row)
      link = row.at_css('a[href*="/app/"]')
      return nil unless link

      cells = row.css('td')
      raw_id = link['href'].to_s.split('/').reject(&:empty?).last

      {
        app_id: raw_id&.to_i,
        name: link.text.strip,
        rank: extract_rank(row, cells),
        value: extract_value(cells),
        url: URI.join(SteamDB::BASE_URL, link['href']).to_s
      }
    rescue URI::InvalidURIError
      nil
    end
    private_class_method :parse_row

    def extract_rank(row, cells)
      if row['data-position']
        Integer(row['data-position'])
      elsif !cells.empty?
        Integer(cells.first.text.strip)
      end
    rescue ArgumentError, TypeError
      nil
    end
    private_class_method :extract_rank

    def extract_value(cells)
      return nil if cells.length < 2

      cells.last.text.strip
    end
    private_class_method :extract_value

    def derive_title_for(table)
      title = table.at_css('thead .table-title')&.text&.strip
      return title unless title.nil? || title.empty?

      title = table.xpath('preceding::h1[1] | preceding::h2[1] | preceding::h3[1]').first
      title&.text&.strip
    end
    private_class_method :derive_title_for
  end
end
