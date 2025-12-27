# steamdb-ruby

A Ruby gem for scraping SteamDB with automatic Cloudflare bypass. Get game data, prices, and screenshots in JSON format.

## Features

- 🆓 **Free Cloudflare bypass** using FlareSolverr
- 📊 **JSON output** for easy integration
- 🎮 **Game data**: info, prices across regions, screenshots
- 📈 **Charts & info**: player charts, languages, DLC, depots
- 🔍 **Search games** and trending lists
- 🚀 **Simple CLI** tool for quick access

## Installation

### In Your Ruby Project (Recommended)

Add to your `Gemfile`:

```ruby
gem 'steamdb', git: 'https://github.com/kirchberg/steamdb-ruby.git'
```

Then install:

```bash
bundle install
```

Or use `bundle add`:

```bash
bundle add steamdb --git https://github.com/kirchberg/steamdb-ruby.git
```

### Global Installation (for CLI only)

```bash
git clone https://github.com/kirchberg/steamdb-ruby.git
cd steamdb-ruby
bundle install
rake build
gem install pkg/steamdb-*.gem
```

## Quick Start

### 1. Start FlareSolverr (required for Cloudflare bypass)

```bash
docker run -d -p 8191:8191 ghcr.io/flaresolverr/flaresolverr:latest
```

Wait 5 seconds for it to start.

### 2. Get game data as JSON

```bash
# If installed via bundler (use bundle exec):
bundle exec steamdb 271590 --pretty

# If installed globally:
steamdb 271590 --pretty

# Save to file
bundle exec steamdb 271590 --pretty > game.json
```

That's it! 🎉

## CLI Usage

```bash
# If using bundler:
bundle exec steamdb [OPTIONS] <app_id>

# If installed globally:
steamdb [OPTIONS] <app_id>

Options:
  --pretty, -p    Pretty print JSON with indentation
  --help, -h      Show help message

Examples:
  bundle exec steamdb 271590 --pretty    # Grand Theft Auto V
  bundle exec steamdb 730                # Counter-Strike: Global Offensive
  bundle exec steamdb 570 > dota2.json   # Dota 2, save to file
```

### Example Output

```json
{
  "app_id": 271590,
  "timestamp": "2025-11-03T12:00:00Z",
  "data": {
    "info": {
      "description": "Grand Theft Auto V for PC...",
      "logo_url": "https://...",
      "library_logo_url": "https://..." // Library logo (image2x/english preferred)
    },
    "prices": [
      {
        "country_code": "us",
        "currency": "U.S. Dollar",
        "price": "29.99",
        "converted_price": "29.99"
      }
      // ... 40 more regions
    ],
    "screenshots": [
      "https://cdn.akamai.steamstatic.com/...",
      // ... more screenshots
    ]
  },
  "summary": {
    "name": "Grand Theft Auto V",
    "developer": "Rockstar North",
    "publisher": "Rockstar Games",
    "prices_count": 41,
    "screenshots_count": 76
  }
}
```

## Ruby API

### Get Game Data

```ruby
require 'steamdb'

# Setup FlareSolverr solver (free Cloudflare bypass)
solver = SteamDB::FlareSolverrSolver.new(session: true)
SteamDB.configure do |client|
  client.configure_captcha(solver: solver, enabled: true)
end

# Fetch game data
game = SteamDB::Game.new(271590)
game.fetch_data
game.parse

# Access data
game.name              # => "Grand Theft Auto V"
game.description       # => "Grand Theft Auto V for PC..."
game.logo_url         # => "https://..." (store header image)
game.library_logo_url # => "https://..." (library logo, image2x/english preferred)
game.prices            # => Array of price hashes
game.screenshots       # => Array of screenshot URLs
```

### Game Info (/info/)

```ruby
info = SteamDB::GameInfo.new(1808500)
info.fetch_data
info.parse

info.data[:languages]     # => Array of supported languages
info.data[:tags]          # => Array of tags
info.data[:dlc]           # => DLC table rows
info.data[:depots]        # => Depot table rows
```

### Game Charts (/charts/)

```ruby
charts = SteamDB::GameCharts.new(1808500)
charts.parse

charts.data[:summary]     # => current/24h/all-time peaks
charts.data[:week]        # => hourly series (start/step in ms)
charts.data[:max]         # => daily series (start/step in ms)
charts.data[:errors]      # => optional error details per endpoint
```

Note: chart APIs may return empty data for apps without public charts.
Requires FlareSolverr; direct requests to chart APIs return 403.

### Export as JSON

```ruby
require 'json'

game = SteamDB::Game.new(271590)
game.fetch_data
game.parse

# Convert to JSON
json_data = {
  app_id: 271590,
  data: game.data,
  summary: {
    name: game.name,
    prices_count: game.prices.length,
    screenshots_count: game.screenshots.length
  }
}

puts JSON.pretty_generate(json_data)
```

### Search Games

```ruby
results = SteamDB.search_games('Portal', limit: 5)
results.each do |result|
  puts "#{result[:name]} (ID: #{result[:app_id]})"
end
```

### Trending Games

```ruby
trending = SteamDB.trending(max_items: 10)
trending.each do |section|
  puts section[:title]
  section[:entries].each do |entry|
    puts "  #{entry[:rank]}. #{entry[:name]}"
  end
end
```

## Using in Your Ruby Project

### Basic Setup

```ruby
# In your Ruby file or Rails initializer
require 'steamdb'

# Configure FlareSolverr (one-time setup)
solver = SteamDB::FlareSolverrSolver.new(
  endpoint: 'http://localhost:8191/v1',
  timeout: 60_000,                       # milliseconds
  session: true                          # Reuse a browser session; set false to disable
)

SteamDB.configure do |client|
  client.configure_captcha(solver: solver, enabled: true)
  # Cache is enabled by default (5 minutes)
  # No throttling needed - FlareSolverr handles rate limiting
end
```

### Example: Rails Service

Create `app/services/steamdb_service.rb`:

```ruby
class SteamDbService
  def initialize
    @solver = SteamDB::FlareSolverrSolver.new(session: true)
    SteamDB.configure { |c| c.configure_captcha(solver: @solver, enabled: true) }
  end

  def get_game_info(app_id)
    game = SteamDB::Game.new(app_id)
    game.fetch_data
    game.parse
    
    {
      name: game.name,
      developer: game.info[:developer],
      publisher: game.info[:publisher],
      prices: game.prices,
      screenshots: game.screenshots
    }
  rescue SteamDB::HTTPError => e
    Rails.logger.error("SteamDB error: #{e.message}")
    nil
  end
end
```

Usage:

```ruby
service = SteamDbService.new
game_data = service.get_game_info(271590)
```

### Example: Background Job

```ruby
class FetchGameDataJob < ApplicationJob
  def perform(app_id)
    game = SteamDB::Game.new(app_id)
    game.fetch_data
    game.parse
    
    # Save to database
    Game.create!(
      steam_app_id: app_id,
      name: game.name,
      data: game.data.to_json
    )
  end
end
```

### Example: API Endpoint

```ruby
# config/routes.rb
get '/api/games/:app_id', to: 'games#show'

# app/controllers/games_controller.rb
class GamesController < ApplicationController
  def show
    game = SteamDB::Game.new(params[:app_id])
    game.fetch_data
    game.parse
    
    render json: {
      app_id: params[:app_id],
      data: game.data,
      summary: {
        name: game.name,
        prices_count: game.prices.length,
        screenshots_count: game.screenshots.length
      }
    }
  rescue SteamDB::HTTPError => e
    render json: { error: e.message }, status: 500
  end
end
```

### Configuration Options

```ruby
SteamDB.configure do |client|
  # Configure FlareSolverr
  solver = SteamDB::FlareSolverrSolver.new(
    endpoint: 'http://localhost:8191/v1',  # FlareSolverr endpoint
    timeout: 60_000,                       # Max wait time (milliseconds)
    session: true                          # Reuse a browser session; set false to disable
  )
  client.configure_captcha(solver: solver, enabled: true)
  
  # Cache configuration (optional)
  client.configure_cache(ttl: 600)  # Cache for 10 minutes (default: 5 minutes)
  
  # Throttling (optional, not needed with FlareSolverr)
  # client.configure_throttle(interval: 1.0)  # Uncomment if needed
  
  # Custom user agents (optional)
  # client.user_agents = ['Custom User Agent/1.0']
end
```

### Per-Worker Clients (Parallel Jobs)

```ruby
SteamDB.with_client(SteamDB::HttpClient.new) do |client|
  solver = SteamDB::FlareSolverrSolver.new(session: true)
  SteamDB.configure(client) { |c| c.configure_captcha(solver: solver, enabled: true) }

  game = SteamDB::Game.new(271590, client: client)
  game.fetch_data
  game.parse
end
```


## Performance & Efficiency

The gem is optimized for efficiency:

- ✅ **Caching**: Responses are cached for 5 minutes by default (configurable)
- ✅ **No throttling by default**: FlareSolverr handles rate limiting automatically
- ✅ **Direct FlareSolverr integration**: No unnecessary retries or delays
- ✅ **Memory-efficient**: Uses in-memory cache that can be replaced with Redis/Memcached

For production, consider using external cache:

```ruby
# Using Redis (example)
class RedisCache
  def initialize(redis_client)
    @redis = redis_client
  end
  
  def fetch(key)
    value = @redis.get(key)
    JSON.parse(value) if value
  end
  
  def write(key, value, expires_in:)
    @redis.setex(key, expires_in.to_i, JSON.generate(value))
    value
  end
end

SteamDB.configure do |client|
  redis = Redis.new(url: ENV['REDIS_URL'])
  client.configure_cache(store: RedisCache.new(redis), ttl: 600)
end
```

## Requirements

- Ruby 3.0+
- Docker (for FlareSolverr)
- FlareSolverr running on `http://localhost:8191`

### Setup FlareSolverr

```bash
# Start FlareSolverr in Docker
docker run -d -p 8191:8191 ghcr.io/flaresolverr/flaresolverr:latest

# Verify it's running
curl http://localhost:8191/v1
```

## Troubleshooting

### FlareSolverr not running

```bash
# Check if running
docker ps | grep flaresolverr

# Start it
docker run -d -p 8191:8191 ghcr.io/flaresolverr/flaresolverr:latest

# Check logs
docker logs flaresolverr
```

### Getting 403 errors

- Make sure FlareSolverr is running and accessible
- Wait a few seconds after starting FlareSolverr
- Try increasing timeout: `timeout: 90_000`

### Empty data fields

Some fields may require additional HTML parsing. The raw HTML is available in the response for custom parsing.

## Data Structure

### Game Data

```ruby
game.data = {
  info: {
    id: 271590,
    name: "Grand Theft Auto V",
    type: "Game",
    developer: "Rockstar North",
    publisher: "Rockstar Games",
    os: ["Windows"],
    release_date: 1428966000000,  # timestamp
    last_update: 1578987453000,   # timestamp
    description: "...",
    logo_url: "https://..."
  },
  prices: [
    {
      country_code: "us",
      currency: "U.S. Dollar",
      price: "29.99",
      converted_price: "29.99"
    }
    # ... more regions
  ],
  screenshots: [
    "https://cdn.akamai.steamstatic.com/...",
    # ... more screenshots
  ]
}
```

## Popular Game App IDs

- `271590` - Grand Theft Auto V
- `730` - Counter-Strike: Global Offensive
- `570` - Dota 2
- `440` - Team Fortress 2
- `1174180` - Red Dead Redemption 2

Find App ID: Visit `https://store.steampowered.com/app/271590` - the number is the App ID.

## Integration Guide

For detailed integration examples in Rails, Sinatra, or other Ruby projects, see [INTEGRATION.md](docs/INTEGRATION.md).

## License

MIT

## Contributing

Contributions welcome! Please feel free to submit a Pull Request.
