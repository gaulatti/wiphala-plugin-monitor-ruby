# Generated by the protocol buffer compiler.  DO NOT EDIT!
# Source: worker.proto for package 'worker'

require "grpc"
require_relative "worker_pb"

module Worker
  module WorkerService
    class Service
      include ::GRPC::GenericService

      self.marshal_class_method = :encode
      self.unmarshal_class_method = :decode
      self.service_name = "worker.WorkerService"

      rpc :PerformTask, ::Worker::WorkerRequest, ::Worker::WorkerResponse
    end

    Stub = Service.rpc_stub_class
  end
end
