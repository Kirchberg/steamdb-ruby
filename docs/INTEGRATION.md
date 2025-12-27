# Integration Guide

## Using steamdb-ruby in Your Ruby Project

### Step 1: Add to Gemfile

```ruby
# Gemfile
gem 'steamdb', git: 'https://github.com/kirchberg/steamdb-ruby.git'
```

Run `bundle install`

### Step 2: Configure (One-time Setup)

Create an initializer (Rails: `config/initializers/steamdb.rb`, or in your startup code):

```ruby
require 'steamdb'

solver = SteamDB::FlareSolverrSolver.new(
  endpoint: ENV.fetch('FLARESOLVERR_URL', 'http://localhost:8191/v1'),
  timeout: 60_000
)

SteamDB.configure do |client|
  client.configure_captcha(solver: solver, enabled: true)
  # Optional: configure cache for production
  # client.configure_cache(ttl: 600)
end
```

### Step 3: Use in Your Code

```ruby
# Simple usage
game = SteamDB::Game.new(271590)
game.fetch_data
game.parse

puts game.name
puts game.prices.length
```

## Rails Integration

### Service Object Pattern

```ruby
# app/services/steamdb_service.rb
class SteamDbService
  def get_game(app_id)
    game = SteamDB::Game.new(app_id)
    game.fetch_data
    game.parse
    
    {
      app_id: app_id,
      name: game.name,
      description: game.description,
      prices: game.prices,
      screenshots: game.screenshots
    }
  rescue SteamDB::HTTPError => e
    Rails.logger.error("SteamDB error for app #{app_id}: #{e.message}")
    nil
  end
end

# Usage in controller
class GamesController < ApplicationController
  def show
    @game_data = SteamDbService.new.get_game(params[:id])
  end
end
```

### Background Jobs

```ruby
# app/jobs/fetch_steam_game_job.rb
class FetchSteamGameJob < ApplicationJob
  queue_as :default

  def perform(app_id)
    game = SteamDB::Game.new(app_id)
    game.fetch_data
    game.parse
    
    # Update database
    steam_game = SteamGame.find_or_initialize_by(app_id: app_id)
    steam_game.update!(
      name: game.name,
      data: game.data
    )
  end
end
```

### API Endpoint

```ruby
# config/routes.rb
namespace :api do
  resources :games, only: [:show]
end

# app/controllers/api/games_controller.rb
class Api::GamesController < ApplicationController
  def show
    game = SteamDB::Game.new(params[:id])
    game.fetch_data
    game.parse
    
    render json: {
      app_id: params[:id],
      data: game.data,
      summary: {
        name: game.name,
        prices_count: game.prices.length,
        screenshots_count: game.screenshots.length
      }
    }
  rescue SteamDB::HTTPError => e
    render json: { error: e.message }, status: :service_unavailable
  end
end
```

## Sinatra Integration

```ruby
require 'sinatra'
require 'steamdb'

# Configure once
solver = SteamDB::FlareSolverrSolver.new
SteamDB.configure { |c| c.configure_captcha(solver: solver, enabled: true) }

get '/games/:app_id' do
  game = SteamDB::Game.new(params[:app_id])
  game.fetch_data
  game.parse
  
  content_type :json
  {
    app_id: params[:app_id],
    data: game.data
  }.to_json
end
```

## Environment Variables

Recommended setup:

```bash
# .env (or environment variables)
FLARESOLVERR_URL=http://localhost:8191/v1
```

Then in your initializer:

```ruby
solver = SteamDB::FlareSolverrSolver.new(
  endpoint: ENV.fetch('FLARESOLVERR_URL', 'http://localhost:8191/v1')
)
```

## Production Considerations

## Recommended Usage Pattern

For most apps, treat SteamDB as a background data source and serve the cached
results to users. This avoids slow requests, reduces Cloudflare risk, and makes
responses stable.

### Background Jobs (Preferred)

- Fetch data in a background job (Sidekiq/ActiveJob/Resque).
- Store parsed JSON in your database.
- In your API/controller, serve the cached JSON.
- For images, store the URLs from SteamDB and render them in the next request.

Example flow:

1. User requests game data.
2. If cache is stale, enqueue background job to refresh.
3. Respond immediately with cached data.
4. Next request sees refreshed data (including image URLs).

### Batching and Concurrency

- Use small batches (10-20 app IDs per run).
- Use limited parallelism (2-4 workers). More can trigger blocks or timeouts.
- If you see disconnects after 1 game, reduce concurrency and increase timeout.

### Caching

- Keep cache enabled; default is 5 minutes.
- For production, use Redis or another shared cache.
- Store parsed JSON to avoid re-parsing on every request.

### 1. FlareSolverr Deployment

Run FlareSolverr as a service:

```yaml
# docker-compose.yml (example)
services:
  flaresolverr:
    image: ghcr.io/flaresolverr/flaresolverr:latest
    ports:
      - "8191:8191"
    restart: unless-stopped
```

Or use environment variable for remote FlareSolverr:

```ruby
SteamDB::FlareSolverrSolver.new(
  endpoint: ENV['FLARESOLVERR_URL']  # e.g., 'http://flaresolverr:8191/v1'
)
```

### 2. Caching

Use Redis for distributed caching:

```ruby
# Using redis gem
require 'redis'
require 'json'

class RedisCache
  def initialize(redis)
    @redis = redis
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

### 3. Error Handling

Always wrap in error handling:

```ruby
def safe_get_game(app_id)
  game = SteamDB::Game.new(app_id)
  game.fetch_data
  game.parse
  game
rescue SteamDB::HTTPError => e
  Rails.logger.error("SteamDB HTTP error: #{e.message}")
  nil
rescue SteamDB::FlareSolverr::Error => e
  Rails.logger.error("FlareSolverr error: #{e.message}")
  nil
rescue StandardError => e
  Rails.logger.error("Unexpected error: #{e.class} - #{e.message}")
  nil
end
```

### 4. Rate Limiting

The gem handles caching automatically. For additional rate limiting at application level:

```ruby
# Using rack-attack or similar
class SteamDbService
  def initialize
    @rate_limiter = RateLimiter.new(max_calls: 10, period: 60)
  end
  
  def get_game(app_id)
    @rate_limiter.call do
      game = SteamDB::Game.new(app_id)
      game.fetch_data
      game.parse
      game
    end
  end
end
```

## Limitations and Constraints

- Requires FlareSolverr; direct requests are likely to be blocked by Cloudflare.
- SteamDB HTML can change; some fields may become unavailable without updates.
- This gem parses the main `/app/:id/` page. It does not parse `/charts/` or
  other sections unless you add custom parsing.
- High concurrency can cause dropped connections or timeouts.
- Images are provided as URLs; you should not hotlink blindly in high-traffic
  contexts. Consider caching or proxying images if needed.

## Testing

```ruby
# spec/services/steamdb_service_spec.rb (RSpec example)
RSpec.describe SteamDbService do
  let(:service) { described_class.new }
  
  context 'when FlareSolverr is available' do
    it 'fetches game data' do
      result = service.get_game(271590)
      
      expect(result).to be_present
      expect(result[:name]).to be_present
    end
  end
  
  context 'when FlareSolverr is unavailable' do
    before do
      allow(SteamDB::FlareSolverrSolver).to receive(:new).and_raise(StandardError)
    end
    
    it 'handles errors gracefully' do
      result = service.get_game(271590)
      expect(result).to be_nil
    end
  end
end
```

## Complete Example

```ruby
# config/initializers/steamdb.rb
require 'steamdb'

unless Rails.env.test?
  solver = SteamDB::FlareSolverrSolver.new(
    endpoint: ENV.fetch('FLARESOLVERR_URL', 'http://localhost:8191/v1')
  )
  
  SteamDB.configure do |client|
    client.configure_captcha(solver: solver, enabled: true)
    
    # Use Redis cache in production
    if defined?(Redis) && ENV['REDIS_URL']
      redis = Redis.new(url: ENV['REDIS_URL'])
      # Implement RedisCache as shown above
      # client.configure_cache(store: RedisCache.new(redis), ttl: 600)
    end
  end
end

# app/services/steamdb_service.rb
class SteamDbService
  class << self
    def get_game_data(app_id)
      game = SteamDB::Game.new(app_id)
      game.fetch_data
      game.parse
      
      {
        app_id: app_id,
        name: game.name,
        description: game.description,
        logo_url: game.logo_url,
        prices: game.prices,
        screenshots: game.screenshots
      }
    rescue SteamDB::Error => e
      Rails.logger.error("SteamDB error for #{app_id}: #{e.message}")
      nil
    end
  end
end
```
