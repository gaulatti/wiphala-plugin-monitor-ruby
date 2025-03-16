require "json"
require "net/http"
require_relative "./worker/worker_services_pb"
require_relative "./orchestrator/orchestrator_services_pb"
require_relative "../clients/bluesky"
require_relative "../clients/gemini"
require_relative "../clients/wiphala"

# THREAD_POOL is a fixed-size thread pool with a maximum of 5 threads.
# It is used to manage and execute concurrent tasks efficiently.
# The thread pool helps in limiting the number of threads running simultaneously,
# which can improve performance and resource utilization.
THREAD_POOL = Concurrent::FixedThreadPool.new(5)

# Initialize the client instances for the Bluesky, Gemini, and Wiphala services.
BLUESKY = BlueskyClient.new
GEMINI = GeminiClient.new
WIPHALA = WiphalaClient.new

# This class implements the gRPC WorkerService defined in the Worker module.
# It inherits from Worker::WorkerService::Service and provides the actual
# implementation of the service methods defined in the gRPC service definition.
class WorkerServiceImpl < Worker::WorkerService::Service
  # Performs a task based on the given request.
  #
  # @param request [Object] The request object containing the payload.
  # @param _unused_call [Object] An unused call object.
  # @return [Worker::WorkerResponse] The response indicating success or failure.
  # @raise [StandardError] If an error occurs during task processing.
  def perform_task(request, _unused_call)
    payload = JSON.parse(request.payload)
    THREAD_POOL.post { process_task(payload, payload["talkback"]) }
    Worker::WorkerResponse.new(success: true)
  rescue StandardError => e
    puts "Error: #{e.message}"
    Worker::WorkerResponse.new(success: false)
  end

  private


  # Processes a task by searching for posts based on provided keywords, filtering newsworthy posts,
  # and sending the results to a specified talkback URL.
  #
  # @param payload [Hash] The payload containing context and metadata information.
  # @param talkback_url [String] The URL to send the newsworthy posts to.
  # @return [Array] An empty array if no keywords are provided.
  #
  # @example
  #   payload = {
  #     "context" => {
  #       "metadata" => {
  #         "keywords" => ["example"],
  #         "keyword" => "example",
  #         "since" => 3600
  #       }
  #     },
  #     "playlist" => {
  #       "slug" => "example_playlist"
  #     }
  #   }
  #   talkback_url = "http://example.com/talkback"
  #   process_task(payload, talkback_url)
  def process_task(payload, talkback_url)
    begin
      keywords = payload["context"]["metadata"]["keywords"] || []

      # Keeping keyword for backwards compatibility
      keyword = payload["context"]["metadata"]["keyword"]
      seconds = payload["context"]["metadata"]["since"]

      unless keyword.nil?
        keywords.push(keyword)
      end

      # If there's no keyword provided, don't do anything.
      return [] if keywords.empty?

      posts = BLUESKY.search_multiple(keywords, seconds)
      newsworthy_posts = GEMINI.filter_newsworthy_posts(posts)

      # Hydrate the newsworthy posts with the full post data
      matched_posts = newsworthy_posts["cids"].map do |cid|
        posts.find { |post| post["cid"] == cid }
      end.compact

      matched_breaking_posts = newsworthy_posts["breaking"].map do |cid|
        posts.find { |post| post["cid"] == cid }
      end.compact

      # Update the newsworthy_posts object to include the full posts
      newsworthy_posts["posts"] = matched_posts
      newsworthy_posts["breaking"] = matched_breaking_posts

      # Remove the cids from the response
      newsworthy_posts.delete("cids")

      # Send the newsworthy posts to the talkback URL
      WIPHALA.talkback(talkback_url, payload["playlist"]["slug"], newsworthy_posts)

    rescue StandardError => e
      puts "❌ Error in process_task: #{e.message}"
      puts e.backtrace.join("\n")
    end
  end
end
