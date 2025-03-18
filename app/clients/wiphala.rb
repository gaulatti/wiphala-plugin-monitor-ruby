
# WiphalaClient is responsible for sending gRPC requests to the Orchestrator service.
#
# Methods:
# - talkback(talkback_url, slug, newsworthy_posts): Sends a gRPC request to update the playlist segue.
#
# Example usage:
#   client = WiphalaClient.new
#   client.talkback("http://localhost:50051", "playlist_slug", [{ title: "Post 1" }, { title: "Post 2" }])
#
# Dependencies:
# - Requires the 'grpc' gem.
# - Requires the 'orchestrator_services_pb' file which defines the Orchestrator gRPC service and messages.
class WiphalaClient
  # Sends a gRPC request to the Orchestrator service to update the playlist segue.
  # @param talkback_url [String] The URL of the gRPC service.
  # @param slug [String] The slug identifier for the playlist.
  # @param newsworthy_posts [Array<Hash>] The list of newsworthy posts to be included in the playlist.
  #
  # @return [void]
  # @raise [StandardError] If the gRPC call fails, an error message and backtrace are printed to the console.
  def talkback(talkback_url, slug, operation, output)
    begin
      uri = URI.parse(talkback_url)
      host = uri.host
      port = uri.port || 50051

      # Create a gRPC channel and client
      stub = Orchestrator::OrchestratorService::Stub.new("#{host}:#{port}", :this_channel_is_insecure)

      # Prepare the gRPC request
      request = Orchestrator::PlaylistSegue.new(
        slug: slug,
        operation: operation,
        output: output.to_json,
      )

      # Send the request
      stub.segue_playlist(request)
    rescue StandardError => e
      puts "❌ gRPC call failed: #{e.message}"
      puts e.backtrace.join("\n")
    end
  end
end
