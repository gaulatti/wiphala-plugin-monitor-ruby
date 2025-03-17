require "net/http"
require "json"
require "uri"

# BlueskyClient is a client for interacting with the Bluesky social media platform.
# It handles authentication, session management, and searching for posts.
#
# Constants:
# BASE_URL - The base URL for the Bluesky API.
# IDENTIFIER - The username for authentication, retrieved from environment variables.
# PASSWORD - The password for authentication, retrieved from environment variables.
#
# Methods:
# initialize - Initializes a new instance of the client and sets the authentication tokens.
# login - Authenticates with the Bluesky API and retrieves access and refresh tokens.
# refresh_session - Refreshes the authentication tokens using the refresh token.
# search - Searches for posts containing the specified term.
#
# Example usage:
# client = BlueskyClient.new
# posts = client.search("example term")
class BlueskyClient
  BASE_URL = "https://bsky.social"
  IDENTIFIER = ENV["BLUESKY_USERNAME"]
  PASSWORD = ENV["BLUESKY_PASSWORD"]

  def initialize
    @auth_token, @refresh_token = login
  end

  def login
    uri = URI("#{BASE_URL}/xrpc/com.atproto.server.createSession")
    response = Net::HTTP.post(uri, { identifier: IDENTIFIER, password: PASSWORD }.to_json, { "Content-Type" => "application/json" })

    if response.is_a?(Net::HTTPSuccess)
      json = JSON.parse(response.body)
      return json["accessJwt"], json["refreshJwt"]
    else
      raise "Failed to log in: #{response.body}"
    end
  end

  # Searches for posts containing the specified term.
  #
  # @param term [String] The search term to query for.
  # @return [Array<Hash>, nil] An array of posts matching the search term, or nil if the search fails.
  #
  # The method performs the following steps:
  # 1. Checks if the authentication token is present.
  # 2. Constructs the URI with the search term and query parameters.
  # 3. Sets up the HTTP GET request with the authorization header.
  # 4. Sends the request and processes the response.
  # 5. If the response is successful, parses and returns the posts.
  # 6. If the token is expired, refreshes the session and retries the search.
  # 7. If the search fails, prints an error message and returns nil.
  def search(term, seconds)
    return unless @auth_token

    uri = URI("#{BASE_URL}/xrpc/app.bsky.feed.searchPosts")

    # Calculate the time `seconds` ago
    since = (Time.now - seconds).utc.iso8601
    # Set up query parameters
    params = {
      q: term,
      sort: "latest",
      since: since
    }
    uri.query = URI.encode_www_form(params)

    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{@auth_token}"

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }

    if response.is_a?(Net::HTTPSuccess)
      result = JSON.parse(response.body)
      result["posts"]
    elsif response.body.include?("ExpiredToken")
      puts "⚠️ Token expired, re-logging in..."
      @auth_token, @refresh_token = login
      search(term, seconds)
    else
      puts "❌ Search failed: #{response.body}"
      nil
    end
  end

  def search_multiple(terms, seconds)
    return unless @auth_token
    return if terms.nil? || terms.empty?

    results = terms.flat_map { |term| search(term, seconds) }.uniq
    results
  end
end
