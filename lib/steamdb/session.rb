# frozen_string_literal: true

require 'http/cookie'

module SteamDB
  # Session helper that simplifies loading cookies sourced from browser automation.
  # Allows providing either HTTP::Cookie instances, cookie headers, or fetching via Playwright.
  class Session
    attr_reader :client

    def initialize(client: SteamDB.client)
      @client = client
    end

    def load_cookies(cookies)
      Array(cookies).each do |cookie|
        case cookie
        when HTTP::Cookie
          client.add_cookie(cookie)
        when Hash
          name = cookie.fetch(:name) { cookie['name'] }
          value = cookie.fetch(:value) { cookie['value'] }
          domain = cookie[:domain] || cookie['domain'] || HttpClient::DEFAULT_DOMAIN
          path = cookie[:path] || cookie['path'] || '/'
          http_cookie = HTTP::Cookie.new(name, value, domain: domain, path: path)
          client.add_cookie(http_cookie)
        else
          raise ArgumentError, "Unsupported cookie type: #{cookie.class}"
        end
      end
    end

    def load_cookie_header(header, uri: HttpClient::TARGET_URI)
      client.load_cookie_header(header, uri: uri)
    end

    def authenticate_with_playwright(url: "#{SteamDB::BASE_URL}/", headless: false, wait_for: nil, solve_captcha: false, **launch_options, &block)
      require 'playwright'

      Playwright.create do |playwright|
        browser = playwright.chromium.launch(headless: headless, **launch_options)
        context = browser.new_context
        page = context.new_page
        page.goto(url, wait_until: wait_for ? 'domcontentloaded' : 'networkidle')
        
        # If CAPTCHA solving is enabled, wait for challenges to be solved
        if solve_captcha
          wait_for_captcha_resolution(page)
        end
        
        block&.call(page)
        page.wait_for_timeout(wait_for * 1000) if wait_for
        cookies = context.cookies
        load_cookies(convert_cookies(cookies))
        cookies
      ensure
        browser&.close
      end
    rescue LoadError
      raise Error, 'playwright-ruby-client gem is required for headless authentication. Add it to your Gemfile to use this helper.'
    end

    def authenticate_with_flaresolverr(solver: nil, url: "#{SteamDB::BASE_URL}/")
      require_relative 'flaresolverr'
      
      # Use provided solver or create new one
      fs_solver = solver || SteamDB::FlareSolverrSolver.new
      
      # Fetch page through FlareSolverr to get cookies
      result = fs_solver.flaresolverr.get(url)
      
      # Apply cookies to client
      result[:cookies].each do |name, value|
        client.set_cookie(name.to_s, value.to_s)
      end
      
      { success: true, cookies_count: result[:cookies].length }
    rescue SteamDB::FlareSolverr::Error => e
      { success: false, error: e.message }
    end

    private

    def convert_cookies(cookies)
      Array(cookies).map do |cookie|
        HTTP::Cookie.new(
          cookie['name'],
          cookie['value'],
          domain: (cookie['domain'] || HttpClient::DEFAULT_DOMAIN),
          path: cookie['path'] || '/',
          secure: cookie['secure'],
          httponly: cookie['httpOnly'],
          expires: cookie['expires'] ? Time.at(cookie['expires']) : nil
        )
      end
    end

    def wait_for_captcha_resolution(page)
      # Wait for Cloudflare challenge to resolve
      max_wait = 30
      start_time = Time.now
      
      loop do
        # Check if we've exceeded max wait time
        break if Time.now - start_time > max_wait

        # Check if challenge is still present
        has_challenge = page.evaluate('() => {
          return document.body.innerText.includes("Checking your browser") ||
                 document.body.innerText.includes("Just a moment") ||
                 document.querySelector(".cf-challenge-running") !== null ||
                 document.querySelector("#challenge-running") !== null;
        }')

        break unless has_challenge

        sleep 0.5
      end
    rescue StandardError => e
      warn "Error waiting for CAPTCHA resolution: #{e.message}"
    end

  end
end
