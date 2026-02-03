# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SteamDB::ChartsOverview do
  it 'parses most played entries from charts overview' do
    document = Nokogiri::HTML(load_fixture('charts_overview.html'))
    allow(SteamDB).to receive(:fetch_page).and_return(document)

    entries = described_class.most_played(max_items: 2)

    expect(entries.length).to eq(2)
    expect(entries[0]).to include(
      app_id: 730,
      name: 'Counter-Strike 2',
      rank: 1,
      current_players: 1_347_214,
      peak_24h: 1_400_000,
      peak_all_time: 1_818_459,
      url: 'https://steamdb.info/app/730/',
      store_url: 'https://store.steampowered.com/app/730/'
    )
    expect(entries[1]).to include(
      app_id: 570,
      name: 'Dota 2',
      rank: 2,
      current_players: 742_031,
      peak_24h: 750_000,
      peak_all_time: 1_295_114,
      url: 'https://steamdb.info/app/570/',
      store_url: 'https://store.steampowered.com/app/570/'
    )
  end

  it 'adds igdb_url when requested' do
    list_doc = Nokogiri::HTML(load_fixture('charts_overview.html'))
    igdb_doc = Nokogiri::HTML(load_fixture('app_charts_with_igdb.html'))
    allow(SteamDB).to receive(:fetch_page).and_return(list_doc, igdb_doc, igdb_doc)

    entries = described_class.most_played(max_items: 2, include_igdb: true)

    expect(entries.map { |entry| entry[:igdb_url] }).to eq([
      'https://www.igdb.com/games/counter-strike-global-offensive?utm_source=SteamDB',
      'https://www.igdb.com/games/counter-strike-global-offensive?utm_source=SteamDB'
    ])
  end
end
