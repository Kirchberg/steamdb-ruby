# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SteamDB::TrendingFollowers do
  it 'parses trending followers entries' do
    document = Nokogiri::HTML(load_fixture('trending_followers.html'))
    allow(SteamDB).to receive(:fetch_page).and_return(document)

    entries = described_class.trending(max_items: 2)

    expect(entries.length).to eq(2)
    expect(entries[0]).to include(
      app_id: 2_483_190,
      name: 'Forza Horizon 6',
      rank: 1,
      percent: 0,
      price: '69,99€',
      rating: '—',
      release_date: 1_779_148_800,
      release_date_text: 'May 2026',
      follows: 129_703,
      gain_7d: 18_581,
      url: 'https://steamdb.info/app/2483190/',
      store_url: 'https://store.steampowered.com/app/2483190/'
    )
    expect(entries[1]).to include(
      app_id: 123,
      name: 'Cairn',
      rank: 2,
      percent: 12,
      price: 'Free',
      rating: '92%',
      release_date: 1_735_689_600,
      release_date_text: 'Jan 2025',
      follows: 98_111,
      gain_7d: 14_785,
      url: 'https://steamdb.info/app/123/',
      store_url: 'https://store.steampowered.com/app/123/'
    )
  end

  it 'adds igdb_url when requested' do
    list_doc = Nokogiri::HTML(load_fixture('trending_followers.html'))
    igdb_doc = Nokogiri::HTML(load_fixture('app_charts_with_igdb.html'))
    allow(SteamDB).to receive(:fetch_page).and_return(list_doc, igdb_doc, igdb_doc)

    entries = described_class.trending(max_items: 2, include_igdb: true)

    expect(entries.map { |entry| entry[:igdb_url] }).to eq([
      'https://www.igdb.com/games/counter-strike-global-offensive?utm_source=SteamDB',
      'https://www.igdb.com/games/counter-strike-global-offensive?utm_source=SteamDB'
    ])
  end
end
