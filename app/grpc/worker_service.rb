require "json"
require "net/http"
require_relative "./worker/worker_services_pb"
require_relative "./orchestrator/orchestrator_services_pb"
require_relative "../clients/bluesky"
require_relative "../clients/gemini"
require_relative "../clients/wiphala"

# To re-generate the pb services:
# grpc_tools_ruby_protoc -I ./protos --ruby_out=./app/grpc/orchestrator
# --grpc_out=./app/grpc/orchestrator protos/orchestrator.proto;
# grpc_tools_ruby_protoc -I ./protos --ruby_out=./app/grpc/worker
# --grpc_out=./app/grpc/worker protos/worker.proto

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


  # The `bluesky` method interacts with the BLUESKY service to search for posts
  # based on provided keywords and a time constraint, and then sends the results
  # to a specified talkback URL.
  #
  # @param payload [Hash] A hash containing the context and metadata for the search.
  #   - `payload["context"]["metadata"]["keywords"]` [Array<String>] (optional) A list of keywords to search for.
  #   - `payload["context"]["metadata"]["keyword"]` [String] (optional) A single keyword for backwards compatibility.
  #   - `payload["context"]["metadata"]["since"]` [Integer] (optional) A timestamp indicating the earliest time for the search.
  #   - `payload["playlist"]["slug"]` [String] The slug identifier for the playlist.
  # @param talkback_url [String] The URL to send the search results to.
  #
  # @return [Array] Returns an empty array if no keywords are provided, otherwise
  #   the method sends the search results to the talkback URL and does not return anything meaningful.
  def bluesky(payload, talkback_url)
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
    WIPHALA.talkback(talkback_url, payload["playlist"]["slug"], "MonitorBluesky", posts)
  end

  # Processes the given payload to filter and handle newsworthy posts, and sends a talkback
  # to the specified URL.
  #
  # @param payload [Hash] The input data containing context and playlist information.
  #   - context [Hash]: Includes a "sequence" array where each slot represents a specific
  #     context. The method looks for a slot with the name "MonitorBluesky".
  #   - playlist [Hash]: Contains a "slug" key used for the talkback.
  # @param talkback_url [String] The URL to send the talkback to.
  #
  # @return [void]
  #
  # The method performs the following steps:
  # 1. Extracts the "MonitorBluesky" slot from the payload's context sequence.
  # 2. Filters the extracted slot for newsworthy posts using the GEMINI module.
  # 3. Ensures the result is a hash by taking the first element if the response is an array.
  # 4. Sends the filtered data to the specified talkback URL using the WIPHALA module.
  def gemini(payload, talkback_url)
    posts = payload["context"]["sequence"].find { |slot|  slot["name"] == "MonitorBluesky" }
    newsworthy_posts = GEMINI.filter_newsworthy_posts(posts)

    # If the response is an array instead of the expected hash, take the first element
    if newsworthy_posts.is_a?(Array)
      newsworthy_posts = newsworthy_posts.first || {}
    end

    WIPHALA.talkback(talkback_url, payload["playlist"]["slug"], "MonitorGemini", newsworthy_posts)
  end

  # Hydrates the payload by enriching the "MonitorGemini" and "MonitorBluesky" sequence slots
  # with additional data and sends the updated output to a talkback URL.
  #
  # @param payload [Hash] The input payload containing context and sequence data.
  #   - Expects "context" key with a "sequence" array of slots.
  #   - Each slot should have a "name" and an "output".
  # @param talkback_url [String] The URL to send the hydrated data to.
  #
  # The method performs the following:
  # - Finds the "MonitorGemini" slot in the sequence and extracts its "output".
  # - Finds the "MonitorBluesky" slot in the sequence and extracts its "output" as posts.
  # - Matches posts based on "cids" in the "MonitorGemini" output and enriches it with full post data.
  # - Optionally processes a "breaking" key in the "MonitorGemini" output to match posts.
  # - Sends the enriched output to the specified talkback URL using the WIPHALA.talkback method.
  def hydrate(payload, talkback_url)
    # Inputs: From Bluesky and Gemini
    output = payload["context"]["sequence"].find { |slot|  slot["name"] == "MonitorGemini" }["output"]
    posts = payload["context"]["sequence"].find { |slot|  slot["name"] == "MonitorBluesky" }["output"]

     # If there are flagged posts, hydrate them from the original source.
     if output.is_a?(Hash) && output["cids"]
      matched_posts = output["cids"].map do |cid|
        posts.find { |post| post["cid"] == cid }
      end.compact

      output["posts"] = matched_posts
      output.delete("cids")
     end

    # If there are breaking posts, hydrate them from the original source.
    if output.is_a?(Hash) && output["breaking"]
      matched_breaking_posts = output["breaking"].map do |cid|
        posts.find { |post| post["cid"] == cid }
      end.compact
      output["breaking"] = matched_breaking_posts
    end

    # Return to sender.
    WIPHALA.talkback(talkback_url, payload["playlist"]["slug"], "MonitorHydrate", output)
  end

  def slack(payload, talkback_url)
    newsworthy_posts = payload["context"]["sequence"].find { |slot|  slot["name"] == "MonitorHydrate" }
    # post to slack
    WIPHALA.talkback(talkback_url, payload["playlist"]["slug"], "MonitorSlack", [])
  end

  # Processes a task based on the provided payload and talkback URL.
  #
  # @param payload [Hash] A hash containing task details, including the "name" key
  #   which determines the type of operation to perform.
  # @param talkback_url [String] A URL used for sending responses or updates related
  #   to the task.
  #
  # @note Supported operations are:
  #   - "MonitorBluesky": Calls the `bluesky` method.
  #   - "MonitorGemini": Calls the `gemini` method.
  #   - "MonitorHydrate": Calls the `hydrate` method.
  #   - "MonitorSlack": Calls the `slack` method.
  #   If the "name" key does not match any of these operations, an "Unknown operation"
  #   message is logged.
  def process_task(payload, talkback_url)
    name = payload["name"]
      case name
      when "MonitorBluesky"
        bluesky(payload, talkback_url)
      when "MonitorGemini"
        gemini(payload, talkback_url)
      when "MonitorHydrate"
        hydrate(payload, talkback_url)
      when "MonitorSlack"
        slack(payload, talkback_url)
      else
        # Handle unknown operation
        puts "Unknown operation: #{name}"
      end
  end
end
