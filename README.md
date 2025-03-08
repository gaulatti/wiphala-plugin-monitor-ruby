# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

- Ruby version

- System dependencies

- Configuration

- Database creation

- Database initialization

- How to run the test suite

- Services (job queues, cache servers, search engines, etc.)

- Deployment instructions

# Notes

To re-generate the protos:

```
grpc_tools_ruby_protoc -I ./protos --ruby_out=./app/grpc/orchestrator --grpc_out=./app/grpc/orchestrator protos/orchestrator.proto;
grpc_tools_ruby_protoc -I ./protos --ruby_out=./app/grpc/worker --grpc_out=./app/grpc/worker protos/worker.proto
```
