# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'digest'
require 'thread'
require 'http/cookie'
require 'http/cookie_jar'

module SteamDB
  HttpResponse = Struct.new(:status, :headers, :body, keyword_init: true) do
    def success?
      status.to_i.between?(200, 299)
    end
  end

  class InMemoryCache
    def initialize
      @store = {}
      @mutex = Mutex.new
    end

    def fetch(key)
      @mutex.synchronize do
        entry = @store[key]
        return nil unless entry

        value, expires_at = entry
        if expires_at && Time.now > expires_at
          @store.delete(key)
          nil
        else
          value
        end
      end
    end

    def write(key, value, expires_in:)
      @mutex.synchronize do
        expiry = expires_in ? Time.now + expires_in.to_f : nil
        @store[key] = [value, expiry]
      end
      value
    end
  end

  class HttpClient
    DEFAULT_DOMAIN = 'steamdb.info'
    TARGET_URI = URI('https://steamdb.info/')

    DEFAULT_TIMEOUT = 10
    DEFAULT_USER_AGENTS = [
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0',
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1'
    ].freeze

    attr_accessor :user_agents, :open_timeout, :read_timeout, :cache_ttl, :captcha_solver
    attr_reader :cookie_jar

    def initialize(user_agents: DEFAULT_USER_AGENTS, open_timeout: DEFAULT_TIMEOUT, read_timeout: DEFAULT_TIMEOUT, cookies: {}, captcha_solver: nil)
      @user_agents = Array(user_agents).reject(&:empty?).dup
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @cookie_jar = HTTP::CookieJar.new
      cookies.each { |name, value| set_cookie(name, value) }
      @throttle_mutex = Mutex.new
      @next_available_at = Time.at(0)
      @throttle_interval = 0  # No throttling by default - FlareSolverr handles rate limiting
      @cache_store = InMemoryCache.new
      @cache_ttl = 300  # 5 minutes default cache
      @user_agent_index = 0
      @captcha_solver = captcha_solver
      @captcha_retry_enabled = true
      @captcha_max_retries = 3
    end

    def fetch(uri, headers: {}, region: 'us')
      request_uri = build_uri(uri)
      header_hash = normalize_headers(headers)
      cache_key = cache_key_for(request_uri, header_hash, region)

      if (cached_response = read_cache(cache_key))
        return cached_response
      end

      throttle!
      response = perform_request_with_captcha_retry(request_uri, headers: header_hash, region: region)
      store_cache(cache_key, response)
      response
    end

    def configure_throttle(interval:)
      @throttle_interval = interval.to_f
    end

    def configure_cache(store: nil, ttl: 60)
      if store
        unless store.respond_to?(:fetch) && store.respond_to?(:write)
          raise ArgumentError, 'cache store must respond to #fetch and #write'
        end
        @cache_store = store
      end
      @cache_ttl = ttl.to_f
    end

    def configure_captcha(solver: nil, enabled: true, max_retries: 3)
      @captcha_solver = solver if solver
      @captcha_retry_enabled = enabled
      @captcha_max_retries = max_retries.to_i
    end

    def captcha_enabled?
      @captcha_retry_enabled && !@captcha_solver.nil?
    end

    private

    def perform_request_with_captcha_retry(uri, headers:, region:)
      # Special handling for FlareSolverr - use it directly for all requests
      if captcha_enabled? && @captcha_solver.is_a?(SteamDB::FlareSolverrSolver)
        return perform_request_via_flaresolverr(uri, headers: headers, region: region)
      end
      
      # Fallback to regular request if FlareSolverr is not configured
      perform_request(uri, headers: headers, region: region)
    end
    
    def perform_request_via_flaresolverr(uri, headers:, region:)
      flaresolverr = @captcha_solver.flaresolverr
      
      # Use FlareSolverr to fetch the page (bypasses Cloudflare automatically)
      result = flaresolverr.get(uri.to_s)
      
      # Apply cookies from FlareSolverr to our cookie jar
      result[:cookies].each do |name, value|
        set_cookie(name.to_s, value.to_s)
      end
      
      # Convert FlareSolverr response to HttpResponse format
      HttpResponse.new(
        status: result[:status],
        headers: result[:headers] || {},
        body: result[:body] || ''
      )
    rescue SteamDB::FlareSolverr::Error => e
      raise HTTPError, "FlareSolverr error: #{e.message}"
    end

    def detect_captcha_challenge(response)
      require_relative 'captcha_detector'
      CaptchaDetector.detect(response)
    end


    def perform_request(uri, headers:, region:)
      header_hash = normalize_headers(headers)

      request = Net::HTTP::Get.new(uri)
      apply_headers(request, header_hash, region)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = @open_timeout
      http.read_timeout = @read_timeout

      raw_response = http.request(request)
      HttpResponse.new(
        status: raw_response.code.to_i,
        headers: raw_response.each_header.to_h,
        body: raw_response.body
      )
    rescue SocketError, Timeout::Error => e
      raise HTTPError, "Failed to fetch #{uri}: #{e.message}"
    end

    def apply_headers(request, headers, region)
      base_headers = {
        'Accept-Language' => 'en-US,en;q=0.5',
        'User-Agent' => next_user_agent,
        'Cookie' => merged_cookies(region, headers['Cookie'])
      }

      (base_headers.merge(headers)).each do |key, value|
        request[key] = value if value
      end
    end

    def merged_cookies(region, extra_cookie_header)
      jar = HTTP::CookieJar.new
      @cookie_jar.cookies.each { |cookie| jar.add(cookie.dup) }
      ensure_region_cookie!(jar, region)

      if extra_cookie_header
        HTTP::Cookie.parse(extra_cookie_header, TARGET_URI).each do |cookie|
          jar.add(cookie)
        end
      end

      jar.cookies(TARGET_URI).map(&:to_s).join('; ')
    end

    def normalize_headers(headers)
      (headers || {}).each_with_object({}) do |(key, value), memo|
        memo[key.to_s] = value
      end
    end

    def next_user_agent
      return DEFAULT_USER_AGENTS.first if @user_agents.empty?

      agent = @user_agents[@user_agent_index % @user_agents.length]
      @user_agent_index += 1
      agent
    end

    def throttle!
      return if @throttle_interval <= 0

      @throttle_mutex.synchronize do
        sleep_time = @next_available_at - Time.now
        sleep(sleep_time) if sleep_time.positive?
        @next_available_at = Time.now + @throttle_interval
      end
    end

    def read_cache(cache_key)
      return nil unless @cache_store && @cache_ttl.positive?

      @cache_store.fetch(cache_key)
    rescue StandardError
      nil
    end

    def store_cache(cache_key, response)
      return response unless @cache_store && @cache_ttl.positive?

      @cache_store.write(cache_key, response, expires_in: @cache_ttl)
    rescue StandardError
      response
    end

    def cache_key_for(uri, headers, region)
      Digest::SHA256.hexdigest([uri.to_s, headers.sort_by { |k, _| k }, region].flatten.join("\u0000"))
    end

    def build_uri(value)
      value.is_a?(URI) ? value : URI(value.to_s)
    end

    def cookies
      @cookie_proxy ||= CookieProxy.new(self)
    end

    def add_cookie(cookie)
      raise ArgumentError, 'cookie must be an HTTP::Cookie' unless cookie.is_a?(HTTP::Cookie)

      @cookie_jar.add(cookie)
    end

    def set_cookie(name, value, domain: DEFAULT_DOMAIN, path: '/')
      cookie = HTTP::Cookie.new(name.to_s, value.to_s, domain: domain, path: path)
      add_cookie(cookie)
    end

    def load_cookie_header(header, uri: TARGET_URI)
      HTTP::Cookie.parse(header.to_s, URI(uri.to_s)).each { |cookie| add_cookie(cookie) }
    end

    def clear_cookie(name)
      @cookie_jar.cookies.each do |cookie|
        if cookie.name.casecmp?(name.to_s)
          @cookie_jar.delete(cookie)
        end
      end
    end

    def cookie_value(name)
      cookie = @cookie_jar.cookies(TARGET_URI).find { |c| c.name.casecmp?(name.to_s) }
      cookie&.value
    end

    def ensure_region_cookie!(jar, region)
      return if jar.cookies(TARGET_URI).any? { |cookie| cookie.name == '__Host-cc' }

      jar.add(HTTP::Cookie.new('__Host-cc', region.to_s, domain: DEFAULT_DOMAIN, path: '/'))
    end

    class CookieProxy
      def initialize(client)
        @client = client
      end

      def []=(name, value)
        @client.set_cookie(name, value)
      end

      def [](name)
        @client.cookie_value(name)
      end

      def delete(name)
        @client.clear_cookie(name)
      end

      def merge!(hash)
        hash.each { |k, v| self[k] = v }
        self
      end
    end

    private :merged_cookies, :next_user_agent, :throttle!, :read_cache, :store_cache,
            :cache_key_for, :build_uri, :ensure_region_cookie!, :perform_request_with_captcha_retry,
            :perform_request_via_flaresolverr, :detect_captcha_challenge
  end
end
