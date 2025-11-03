# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module SteamDB
  # FlareSolverr integration for free Cloudflare bypass
  # https://github.com/FlareSolverr/FlareSolverr
  #
  # FlareSolverr is a free, open-source proxy server that bypasses Cloudflare
  # by using a real browser (Chrome/Firefox) to solve challenges automatically.
  #
  # Setup:
  #   docker run -d -p 8191:8191 ghcr.io/flaresolverr/flaresolverr:latest
  #
  # Usage:
  #   flaresolverr = SteamDB::FlareSolverr.new(endpoint: 'http://localhost:8191/v1')
  #   SteamDB.configure { |c| c.configure_flaresolverr(flaresolverr) }
  class FlareSolverr
    class Error < StandardError; end
    class TimeoutError < Error; end
    class ChallengeError < Error; end

    DEFAULT_ENDPOINT = 'http://localhost:8191/v1'
    DEFAULT_TIMEOUT = 60_000 # milliseconds

    attr_reader :endpoint, :timeout, :session_id

    # Initialize FlareSolverr client
    # @param endpoint [String] FlareSolverr API endpoint
    # @param timeout [Integer] Maximum time to wait for challenge solving (milliseconds)
    # @param max_timeout [Integer] Maximum allowed timeout (milliseconds)
    def initialize(endpoint: DEFAULT_ENDPOINT, timeout: DEFAULT_TIMEOUT, max_timeout: 120_000)
      @endpoint = endpoint
      @timeout = [timeout, max_timeout].min
      @max_timeout = max_timeout
      @session_id = nil
    end

    # Create a persistent session
    # Sessions reuse the same browser instance for better performance
    # @return [String] Session ID
    def create_session
      response = make_request(
        cmd: 'sessions.create'
      )

      @session_id = response['session']
      @session_id
    end

    # Destroy the current session
    def destroy_session
      return unless @session_id

      make_request(
        cmd: 'sessions.destroy',
        session: @session_id
      )

      @session_id = nil
    end

    # Get request through FlareSolverr (bypasses Cloudflare)
    # @param url [String] URL to fetch
    # @param max_timeout [Integer] Override timeout for this request
    # @return [Hash] Response with :status, :headers, :body, :cookies
    def get(url, max_timeout: nil)
      params = {
        cmd: 'request.get',
        url: url,
        maxTimeout: max_timeout || @timeout
      }

      params[:session] = @session_id if @session_id

      response = make_request(params)
      solution = response['solution']

      unless solution
        raise ChallengeError, "No solution returned from FlareSolverr"
      end

      {
        status: solution['status'],
        headers: solution['headers'] || {},
        body: solution['response'],
        cookies: parse_cookies(solution['cookies'] || []),
        user_agent: solution['userAgent']
      }
    end

    # Post request through FlareSolverr
    # @param url [String] URL to post to
    # @param post_data [String] POST data
    # @param max_timeout [Integer] Override timeout for this request
    # @return [Hash] Response with :status, :headers, :body, :cookies
    def post(url, post_data: nil, max_timeout: nil)
      params = {
        cmd: 'request.post',
        url: url,
        maxTimeout: max_timeout || @timeout
      }

      params[:postData] = post_data if post_data
      params[:session] = @session_id if @session_id

      response = make_request(params)
      solution = response['solution']

      unless solution
        raise ChallengeError, "No solution returned from FlareSolverr"
      end

      {
        status: solution['status'],
        headers: solution['headers'] || {},
        body: solution['response'],
        cookies: parse_cookies(solution['cookies'] || []),
        user_agent: solution['userAgent']
      }
    end

    # Check if FlareSolverr is available
    # @return [Boolean]
    def available?
      uri = URI(@endpoint)
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 5
      http.read_timeout = 5

      response = http.get(uri.path)
      response.is_a?(Net::HTTPSuccess)
    rescue StandardError
      false
    end

    # Get FlareSolverr version info
    # @return [Hash] Version information
    def version
      # FlareSolverr doesn't have a version endpoint, but we can check the root
      uri = URI(@endpoint)
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 5
      http.read_timeout = 5

      response = http.get('/')
      if response.is_a?(Net::HTTPSuccess)
        { status: 'running', endpoint: @endpoint }
      else
        { status: 'unknown', endpoint: @endpoint }
      end
    rescue StandardError => e
      { status: 'error', error: e.message, endpoint: @endpoint }
    end

    private

    def make_request(params)
      uri = URI(@endpoint)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = 10
      http.read_timeout = (@timeout / 1000) + 10 # Add buffer to HTTP timeout

      request = Net::HTTP::Post.new(uri.path)
      request['Content-Type'] = 'application/json'
      request.body = params.to_json

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "FlareSolverr HTTP error: #{response.code} #{response.message}"
      end

      result = JSON.parse(response.body)

      if result['status'] == 'error'
        error_msg = result['message'] || 'Unknown error'
        raise Error, "FlareSolverr error: #{error_msg}"
      end

      result
    rescue JSON::ParserError => e
      raise Error, "Failed to parse FlareSolverr response: #{e.message}"
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise TimeoutError, "FlareSolverr timeout: #{e.message}"
    rescue StandardError => e
      raise Error, "FlareSolverr request failed: #{e.message}"
    end

    def parse_cookies(cookies_array)
      cookies_array.each_with_object({}) do |cookie, hash|
        hash[cookie['name']] = cookie['value']
      end
    end
  end

  # Base class for CAPTCHA solving
  class CaptchaSolver
    class SolverError < StandardError; end
    class TimeoutError < SolverError; end
    class BalanceError < SolverError; end

    attr_reader :timeout, :poll_interval

    def initialize(timeout: 120, poll_interval: 3, **options)
      @timeout = timeout
      @poll_interval = poll_interval
    end
  end

  # FlareSolverr-based CAPTCHA solver (free)
  class FlareSolverrSolver < CaptchaSolver
    attr_reader :flaresolverr

    def initialize(endpoint: FlareSolverr::DEFAULT_ENDPOINT, timeout: 60_000, **options)
      super(timeout: timeout / 1000, **options)
      @flaresolverr = FlareSolverr.new(endpoint: endpoint, timeout: timeout)
    end

    def available?
      @flaresolverr.available?
    end
  end
end

