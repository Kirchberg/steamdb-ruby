# frozen_string_literal: true

module SteamDB
  class GameCharts
    attr_reader :data, :errors

    def initialize(game_id, region: 'us', client: SteamDB.client)
      @game_id = game_id.to_s
      @region = region.to_s
      @client = client
      @page = nil
      @errors = []
      @data = {}
    end

    def fetch_data
      @page = SteamDB.fetch_page("/app/#{@game_id}/charts/", region: @region, client: @client)
      self
    rescue HTTPError => e
      raise Error, "Unable to fetch charts #{@game_id}: #{e.message}"
    end

    def parse
      @errors = []

      week = fetch_graph('GetGraphWeek')
      max = fetch_graph('GetGraphMax')

      summary = build_summary(week, max)
      summary = merge_meta_summary(summary, @page) if @page

      @data = {
        app_id: @game_id.to_i,
        week: week,
        max: max,
        summary: summary
      }

      @data[:errors] = @errors unless @errors.empty?
      @data
    end

    private

    def fetch_graph(endpoint)
      json = SteamDB.fetch_json("/api/#{endpoint}/?appid=#{@game_id}", region: @region, headers: api_headers, client: @client)
      unless json[:success]
        @errors << { endpoint: endpoint, error: json[:error] || 'Request failed' }
        return nil
      end

      data = json[:data] || {}
      normalize_series(data)
    rescue SteamDB::HTTPError => e
      @errors << { endpoint: endpoint, error: e.message }
      nil
    end

    def api_headers
      {
        'Accept' => 'application/json',
        'X-Requested-With' => 'XMLHttpRequest'
      }
    end

    def normalize_series(data)
      start = data[:start].to_i
      step = data[:step].to_i
      values = Array(data[:values])

      {
        start: start * 1000,
        step: step * 1000,
        values: values
      }
    end

    def build_summary(week, max)
      summary = {}

      current = last_value(week)
      summary[:current_players] = current[:value] if current
      summary[:current_players_at] = current[:timestamp] if current

      peak_24 = peak_window(week, 24 * 60 * 60 * 1000)
      summary[:peak_24h] = peak_24[:value] if peak_24
      summary[:peak_24h_at] = peak_24[:timestamp] if peak_24

      peak_all = peak_all_time(max)
      summary[:peak_all_time] = peak_all[:value] if peak_all
      summary[:peak_all_time_at] = peak_all[:timestamp] if peak_all

      summary
    end

    def last_value(series)
      return nil unless series

      values = series[:values]
      return nil if values.nil? || values.empty?
      return nil if series[:start].to_i <= 0 || series[:step].to_i <= 0

      idx = values.rindex { |value| !value.nil? }
      return nil unless idx

      {
        value: values[idx].to_i,
        timestamp: series[:start] + series[:step] * idx
      }
    end

    def peak_window(series, window_ms)
      return nil unless series

      values = series[:values]
      return nil if values.nil? || values.empty?
      return nil if series[:start].to_i <= 0 || series[:step].to_i <= 0

      window_points = (window_ms.to_f / series[:step].to_f).ceil
      start_idx = [values.length - window_points, 0].max
      slice = values[start_idx..] || []
      peak_value = slice.compact.max
      return nil if peak_value.nil?

      idx_in_slice = slice.rindex(peak_value)
      idx = start_idx + idx_in_slice

      {
        value: peak_value.to_i,
        timestamp: series[:start] + series[:step] * idx
      }
    end

    def peak_all_time(series)
      return nil unless series

      values = series[:values]
      return nil if values.nil? || values.empty?
      return nil if series[:start].to_i <= 0 || series[:step].to_i <= 0

      peak_value = values.compact.max
      return nil if peak_value.nil?

      idx = values.rindex(peak_value)
      return nil unless idx

      {
        value: peak_value.to_i,
        timestamp: series[:start] + series[:step] * idx
      }
    end

    def merge_meta_summary(summary, page)
      meta = parse_meta_summary(page)
      return summary if meta.empty?

      merged = summary.dup
      meta.each do |key, value|
        merged[key] = value if merged[key].nil?
      end
      merged
    end

    def parse_meta_summary(page)
      description = page.at_css('meta[name="description"]')&.[]('content') ||
                    page.at_css('meta[property="og:description"]')&.[]('content')
      return {} if description.nil? || description.empty?

      {
        current_players: extract_number(description, /currently\s+([\d,]+)/i),
        peak_24h: extract_number(description, /24-hour peak of\s+([\d,]+)/i),
        peak_all_time: extract_number(description, /all-time peak of\s+([\d,]+)/i)
      }.compact
    end

    def extract_number(text, regex)
      match = text.match(regex)
      return nil unless match

      match[1].to_s.gsub(/[^\d]/, '').to_i
    end
  end
end
