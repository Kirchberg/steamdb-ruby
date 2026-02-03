# frozen_string_literal: true

module SteamDB
  module IgdbLink
    module_function

    def extract(page)
      link = page.at_css('a[href*="igdb.com/games/"]') || page.at_css('a[href*="igdb.com"]')
      link&.[]('href')&.strip
    end

    def fetch(app_id, region:, client:)
      return nil unless app_id && app_id.to_i.positive?

      page = SteamDB.fetch_page("/app/#{app_id}/charts/", region: region, client: client)
      extract(page)
    rescue SteamDB::HTTPError
      nil
    end
  end
end
