# StreamServer

## Start gRPC Server

```bash
iex -S mix
``` 

## Send unary request

```bash
grpcurl -plaintext -d '{"name": "Joe"}' localhost:50051 stream.EchoServer/SayUnaryHello
``` 

## Send Server stream request

```bash
grpcurl -plaintext -d '{"name": "Valim"}' localhost:50051 stream.EchoServer/SayServerHello
``` 

## Send Streamed request

1. Generate fake data
```bash
./generate_data.sh
``` 

2. Make request
```bash
cat bulk_input.json | grpcurl -plaintext -d @ localhost:50051 stream.EchoServer/SayBidStreamHello
``` 