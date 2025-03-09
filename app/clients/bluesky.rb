require "net/http"
require "json"
require "uri"

# BlueskyClient is a client for interacting with the Bluesky social media platform.
# It provides methods for logging in and searching for posts.
#
# Constants:
# BASE_URL - The base URL for the Bluesky API.
# IDENTIFIER - The username for authentication, retrieved from environment variables.
# PASSWORD - The password for authentication, retrieved from environment variables.
#
# Methods:
# initialize - Initializes a new instance of the client and sets the authentication token.
# login - Logs in to the server and retrieves an access JWT.
# search - Searches for posts containing the specified term.
#
# Example usage:
# client = BlueskyClient.new
# posts = client.search("example term")
# if posts
#   posts.each do |post|
#     puts post["content"]
#   end
# else
#   puts "No posts found or search failed."
class BlueskyClient
  BASE_URL = "https://bsky.social"
  IDENTIFIER = ENV["BLUESKY_USERNAME"]
  PASSWORD = ENV["BLUESKY_PASSWORD"]

  # Initializes a new instance of the client and sets the authentication token.
  # The authentication token is obtained by calling the login method.
  def initialize
    @auth_token = login
  end

  # Logs in to the server and retrieves an access JWT.
  #
  # @return [String] the access JWT if login is successful
  # @raise [RuntimeError] if the login request fails
  def login
    uri = URI("#{BASE_URL}/xrpc/com.atproto.server.createSession")
    response = Net::HTTP.post(uri, { identifier: IDENTIFIER, password: PASSWORD }.to_json, { "Content-Type" => "application/json" })

    if response.is_a?(Net::HTTPSuccess)
      json = JSON.parse(response.body)
      json["accessJwt"]
    else
      raise "Failed to log in: #{response.body}"
      nil
    end
  end

  # Searches for posts containing the specified term.
  #
  # @param term [String] The search term to query for.
  # @return [Array<Hash>, nil] An array of posts if the search is successful, or nil if the search fails.
  #
  # @note This method requires an authentication token (@auth_token) to be set.
  # @note The search is limited to posts from the last 5 minutes.
  #
  # @example
  #   posts = search("example term")
  #   if posts
  #     posts.each do |post|
  #       puts post["content"]
  #     end
  #   else
  #     puts "No posts found or search failed."
  def search(term)
    return unless @auth_token

    uri = URI("#{BASE_URL}/xrpc/app.bsky.feed.searchPosts")

    # Calculate the time 10 minutes ago
    five_minutes_ago = (Time.now - 600).utc.iso8601

    # Set up query parameters
    params = {
      q: term,
      sort: "latest",
      since: five_minutes_ago
    }
    uri.query = URI.encode_www_form(params)

    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{@auth_token}"

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }

    if response.is_a?(Net::HTTPSuccess)
      result = JSON.parse(response.body)
      result["posts"]
    else
      puts "Search failed: #{response.body}"
      nil
    end
  end
end
