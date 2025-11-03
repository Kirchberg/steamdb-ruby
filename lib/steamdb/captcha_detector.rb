# frozen_string_literal: true

module SteamDB
  # Detects CAPTCHA challenges in HTTP responses
  class CaptchaDetector
    # Cloudflare challenge indicators
    CLOUDFLARE_INDICATORS = [
      /cf-challenge/i,
      /cf_chl_/i,
      /cf-browser-verification/i,
      /Checking your browser/i,
      /Just a moment/i,
      /Enable JavaScript and cookies to continue/i,
      /Ray ID:/i,
      /cloudflare/i
    ].freeze

    # Turnstile CAPTCHA indicators
    TURNSTILE_INDICATORS = [
      /turnstile/i,
      /cf-turnstile/i,
      /data-sitekey/i,
      /challenges\.cloudflare\.com/i
    ].freeze

    # Check if response contains a CAPTCHA challenge
    # @param response [HttpResponse] The HTTP response to check
    # @return [Hash, nil] Challenge details or nil if no challenge detected
    def self.detect(response)
      return nil unless response
      return nil if response.success? && !contains_challenge?(response.body)

      challenge_type = identify_challenge_type(response)
      return nil unless challenge_type

      {
        type: challenge_type,
        url: extract_challenge_url(response),
        sitekey: extract_sitekey(response.body),
        body: response.body,
        headers: response.headers
      }
    end

    # Check if response body contains challenge indicators
    # @param body [String] Response body
    # @return [Boolean]
    def self.contains_challenge?(body)
      return false unless body.is_a?(String)

      CLOUDFLARE_INDICATORS.any? { |pattern| body.match?(pattern) }
    end

    # Identify the type of challenge
    # @param response [HttpResponse] The HTTP response
    # @return [Symbol, nil] Challenge type or nil
    def self.identify_challenge_type(response)
      body = response.body
      return nil unless body

      if TURNSTILE_INDICATORS.any? { |pattern| body.match?(pattern) }
        :turnstile
      elsif CLOUDFLARE_INDICATORS.any? { |pattern| body.match?(pattern) }
        :cloudflare
      elsif response.status == 403 || response.status == 503
        :cloudflare # Generic Cloudflare challenge
      end
    end

    # Extract Turnstile sitekey from HTML
    # @param html [String] HTML content
    # @return [String, nil] Sitekey or nil
    def self.extract_sitekey(html)
      return nil unless html

      # Try multiple patterns to extract sitekey
      patterns = [
        /data-sitekey=["']([^"']+)["']/,
        /sitekey:\s*["']([^"']+)["']/,
        /<input[^>]+name=["']cf-turnstile-response["'][^>]+data-sitekey=["']([^"']+)["']/,
        /window\._cf_chl_opt\s*=\s*\{[^}]*sitekey:\s*["']([^"']+)["']/
      ]

      patterns.each do |pattern|
        match = html.match(pattern)
        return match[1] if match
      end

      nil
    end

    # Extract challenge URL from response
    # @param response [HttpResponse] The HTTP response
    # @return [String, nil] Challenge URL or nil
    def self.extract_challenge_url(response)
      # Try to get from Location header (redirect)
      location = response.headers['location']
      return location if location

      # Try to extract from HTML meta refresh
      if response.body
        meta_match = response.body.match(/<meta[^>]+http-equiv=["']refresh["'][^>]+content=["'][^"]*url=([^"']+)["']/i)
        return meta_match[1] if meta_match
      end

      nil
    end

    # Check if status code indicates a challenge
    # @param status [Integer] HTTP status code
    # @return [Boolean]
    def self.challenge_status?(status)
      [403, 503].include?(status.to_i)
    end

    # Extract Ray ID from Cloudflare response (useful for debugging)
    # @param html [String] HTML content
    # @return [String, nil] Ray ID or nil
    def self.extract_ray_id(html)
      return nil unless html

      match = html.match(/Ray ID:\s*([a-f0-9]+)/i) ||
              html.match(/data-ray=["']([^"']+)["']/i) ||
              html.match(/cf-ray:\s*([a-f0-9\-]+)/i)
      
      match[1] if match
    end

    # Check if response indicates rate limiting
    # @param response [HttpResponse] The HTTP response
    # @return [Boolean]
    def self.rate_limited?(response)
      return false unless response

      status = response.status.to_i
      return true if status == 429

      # Check for rate limit indicators in body
      if response.body
        rate_limit_patterns = [
          /rate limit/i,
          /too many requests/i,
          /slow down/i
        ]
        
        return true if rate_limit_patterns.any? { |pattern| response.body.match?(pattern) }
      end

      false
    end

    # Get retry-after duration from response headers
    # @param response [HttpResponse] The HTTP response
    # @return [Integer, nil] Seconds to wait or nil
    def self.retry_after(response)
      return nil unless response

      retry_header = response.headers['retry-after']
      return nil unless retry_header

      # Can be either seconds or HTTP date
      if retry_header.match?(/^\d+$/)
        retry_header.to_i
      else
        # Parse HTTP date and calculate difference
        begin
          retry_time = Time.httpdate(retry_header)
          [retry_time - Time.now, 0].max.to_i
        rescue ArgumentError
          nil
        end
      end
    end
  end
end

