# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SteamDB::Upcoming do
  it 'parses upcoming releases with 7d gain' do
    document = Nokogiri::HTML(load_fixture('upcoming_default.html'))
    allow(SteamDB).to receive(:fetch_page).and_return(document)

    entries = described_class.upcoming(max_items: 1)

    expect(entries.length).to eq(1)
    expect(entries[0]).to include(
      app_id: 3_681_010,
      name: 'Nioh 3',
      rank: 1,
      percent: 0,
      price: '79,99€',
      rating: '—',
      release_date: 1_770_336_000,
      release_date_text: '06 Feb',
      follows: 39_135,
      gain_7d: 6_316,
      url: 'https://steamdb.info/app/3681010/',
      store_url: 'https://store.steampowered.com/app/3681010/'
    )
  end

  it 'parses upcoming releases with online and peak columns' do
    document = Nokogiri::HTML(load_fixture('upcoming_lastweek.html'))
    allow(SteamDB).to receive(:fetch_page).and_return(document)

    entries = described_class.upcoming(max_items: 1, lastweek: true, min_rating: 65, sort: 'peak_desc')

    expect(entries.length).to eq(1)
    expect(entries[0]).to include(
      app_id: 1_588_550,
      name: 'Cairn',
      rank: 1,
      percent: 10,
      price: '26,99€',
      rating: '91.08%',
      release_date: 1_769_644_800,
      release_date_text: '29 Jan',
      follows: 52_647,
      online: 9_090,
      peak: 14_996,
      url: 'https://steamdb.info/app/1588550/',
      store_url: 'https://store.steampowered.com/app/1588550/'
    )
  end
end
