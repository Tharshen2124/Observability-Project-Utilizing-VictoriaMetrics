---
name: Restructure-Plan
description: This document is for the agent and the developer to reference on the restructuring needed to be done for this project
---

# Context
The current project state at the time of writing this is that it has single Go service that has 3 entities which are the orders, products and users. The goal of htis project is to showcase and built a pipeline that takes telemetry data which are metrics, logs and traces and pushes them to the respective services which are VictoriaMetrics, VictoriaLogs, VictoriaTraces and the AWS S3 bucket (which is for storing logs too). Grafana is also used here but it pulls its data from the volumes of the Victoria services. 

# Stage 1 Improvements - convert to microservice pattern

## 1. Implementing an API gateway
Each of the services will also be communicating with an API gateway which would be another service built to be the middleman of connecting our client and the microservices. The client will communicate with the gateway via REST but the gateway and direct those calls to the microservices via gRPC.

## 2. Restructure to a microservice architecture
The Go service is going to be restructured where it will consist of 3 microservices which are the Order service, Product service and User service. The services will communicate with each other via gRPC. The reason for this is gRPC is great for high performance connections between internal services, which makes learning on how its implemented worth the trouble. 

## 3. Resolve the `CreateOrder` method
For this method, it will require updating the product's database followed by the order's database. IF the order's one fails, the transaction that is already commited to the product's database will remain. This is where we look into saga patterns. The idea is that we update one DB's transaction then the other, if the upcoming one fails, we use a compensation transaction to remove that previous commited transaction. We can use the orchestrate-based coordination saga. 

**Need to read more** but based on suggestion from AI, orchestration based is simpler where the Order service is the one calling the shots in case anything fails. Choreography-based saga is overkill as both services will listen to each other's events.

## 4. The database will be isolated per service
So since we are going for true microservice based approach, its better to just do that and follow the way of having isolated databases for each service. 



