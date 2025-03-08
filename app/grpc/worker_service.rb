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

  # Processes a task by searching for posts, filtering newsworthy posts, and sending them to a talkback URL.
  #
  # @param payload [Hash] the payload containing task details, including the search term and slug.
  # @param talkback_url [String] the URL to send the filtered newsworthy posts to.
  #
  # @raise [StandardError] if any error occurs during the processing of the task.
  #
  # @example
  #   payload = { "search_term" => "example term", "slug" => "example-slug" }
  #   talkback_url = "http://example.com/talkback"
  #   process_task(payload, talkback_url)
  def process_task(payload, talkback_url)
    begin

      # TODO: REMOVE WHEN RECEIVING FROM ORCHESTRATOR
      payload["search_term"] = "bahia blanca"

      posts = BLUESKY.search(payload["search_term"])
      newsworthy_posts = GEMINI.filter_newsworthy_posts(posts)
      WIPHALA.talkback(talkback_url, payload["slug"], newsworthy_posts)

    rescue StandardError => e
      puts "❌ Error in process_task: #{e.message}"
      puts e.backtrace.join("\n")
    end
  end
end
