require "net/http"
require "json"
require "uri"

# The `GeminiClient` class provides methods to interact with the Gemini API for content analysis.
# It includes functionality to filter newsworthy posts based on the API's analysis.
#
# Constants:
# - `API_KEY`: The API key for authenticating with the Gemini API, retrieved from environment variables.
# - `MODEL`: The model identifier used for the Gemini API.
# - `SAFETY_SETTINGS`: An array of safety settings to configure the API's content moderation.
#
# Methods:
# - `initialize`: Initializes a new instance of the client and sets up the URI for the Gemini API.
# - `filter_newsworthy_posts`: Filters the given posts to determine which ones are newsworthy.
#
# Example usage:
#   client = GeminiClient.new
#   newsworthy_posts = client.filter_newsworthy_posts(posts)
class GeminiClient
  API_KEY = ENV["GEMINI_API_KEY"]
  MODEL = "gemini-2.0-flash-exp"

  SAFETY_SETTINGS = [
    { category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_NONE" },
    { category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_NONE" },
    { category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_NONE" },
    { category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_NONE" },
    { category: "HARM_CATEGORY_CIVIC_INTEGRITY", threshold: "BLOCK_NONE" }
  ]

  # Initializes a new instance of the client and sets up the URI for the Gemini API.
  # The URI is constructed using the provided model and API key.
  #
  # @example
  #   client = GeminiClient.new
  #
  # @note
  #   Ensure that MODEL and API_KEY are defined and valid before initializing the client.
  def initialize
    @uri = URI("https://generativelanguage.googleapis.com/v1beta/models/#{MODEL}:generateContent?key=#{API_KEY}")
  end

  # Filters the given posts to determine which ones are newsworthy.
  #
  # @param posts [Array<Hash>] an array of posts to be analyzed.
  # @return [Array<Hash>] an array of posts that are determined to be newsworthy.
  #
  # The method sends the posts to an external API for analysis. Each post is converted
  # to JSON and included in a prompt that asks the API to determine if each post is
  # newsworthy. The API response is parsed to extract the results, and only the posts
  # marked as newsworthy are returned.
  #
  # If the API request fails, an error message is printed and an empty array is returned.
  def filter_newsworthy_posts(posts)
    return [] if posts.nil? || posts.empty?

    prompts = posts.map.with_index do |post, index|
      "Post #{index + 1}:\n#{post.to_json}\n"
    end

    combined_prompt = <<~PROMPT
      Analyze the following posts and determine which are newsworthy.
      For each newsworthy post, extract:
      - Relevant categories (e.g., Politics, Technology, Sports, etc.)
      - If it's a breaking news event, extract the event type (e.g., Earthquake, Fire) and the urgency.
      - Important newsworthy keywords worth exploring.

      Instead of returning an array of objects, return a JSON object with two keys:
        - "breaking": an array containing the cid values of all breaking news posts.
        - "cids": an array containing the cid values of all non breaking news newsworthy posts (not in "breaking").
        - "keywords": an array containing the 15 most relevant categories and keywords (combined) across all posts, prioritized by urgency and newsworthiness.

      IMPORTANT: For the analysis, only consider the text portion of every post record, not embeds.
      IMPORTANT: Avoid posts that are mostly opinion or commentary. Focus on posts that provide factual information or report on events.
      IMPORTANT: Your response MUST be ONLY valid JSON. DO NOT include any markdown formatting,
      code fences, or extra text. Output the JSON verbatim.

      #{prompts.join("\n")}
    PROMPT

    request_body = {
      contents: [ { parts: [ { text: combined_prompt } ] } ],
      safetySettings: SAFETY_SETTINGS
    }.to_json

    request = Net::HTTP::Post.new(@uri, { "Content-Type" => "application/json" })
    request.body = request_body

    response = Net::HTTP.start(@uri.host, @uri.port, use_ssl: true) { |http| http.request(request) }

    if response.is_a?(Net::HTTPSuccess)
      json = JSON.parse(response.body)
      output = json.dig("candidates", 0, "content", "parts", 0, "text").to_s.strip
      # Extract JSON content if wrapped in markdown code fences
      json_output = if output =~ /```json\s*(.*?)\s*```/m
        $1.strip
      else
        output
      end

      if json_output.start_with?("[") && !json_output.strip.end_with?("]")
        last_brace_index = json_output.rindex("}")
        if last_brace_index
          recovered_output = json_output[0..last_brace_index] + "]"
          begin
            newsworthy_posts = JSON.parse(recovered_output)
          rescue JSON::ParserError => e
            puts "❌ Recovery failed: #{e.message}"
            newsworthy_posts = []
          end
        else
          newsworthy_posts = []
        end
      else
        begin
          newsworthy_posts = JSON.parse(json_output)
        rescue JSON::ParserError => e
          puts "❌ Failed to parse API response: #{json_output}"
          newsworthy_posts = []
        end
      end
      newsworthy_posts
    else
      puts "❌ Gemini API failed: #{response.body}"
      []
    end
  end
end
