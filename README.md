# Backend Engineering Take-Home Assignment: Dynamic Pricing Proxy

## The Challenge

At Tripla, we use a dynamic pricing model for hotel rooms. Instead of static, unchanging rates, our model uses a real-time algorithm to adjust prices based on market demand and other data signals. This helps us maximize both revenue and occupancy.

Our Data and AI team built a powerful model to handle this, but its inference process is computationally expensive to run. To make this product more cost-effective, we analyzed the model's output and found that a calculated room rate remains effective for up to 5 minutes.

This insight presents a great optimization opportunity, and that's where you come in.

## Your Mission

Your mission is to build an efficient service that acts as an intermediary to our dynamic pricing model. This service will be responsible for providing rates to our users while respecting the operational constraints of the expensive model behind it.

You will start with a Ruby on Rails application that is already integrated with our dynamic pricing model. However, the current implementation fetches a new rate for every single request. Your mission is to ensure this service handles the pricing models' constraints.

## Core Requirements

1. Pricing model's API is limited to **1,000 requests per day**. The pricing model's API, docker image, and documentation are hosted on dockerhub:  [tripladev/rate-api](https://hub.docker.com/r/tripladev/rate-api).

2. Ensure rate validity. A rate fetched from the pricing model is considered **valid for 5 minutes**. Your service must ensure that any rate it provides for a given set of parameters (`period`, `hotel`, `room`) is no older than this 5-minute window.

3. Honor throughput requirements. Your solution must be able to handle at least **10,000 requests per day** from our users while using a single API token.

### Quick Start Guide

Here is a list of common commands for building, running, and interacting with the Dockerized environment.

```bash

# --- 1. Build & Run The Main Application ---
# Build and run the Docker compose
docker compose up -d --build

# --- 2. Test The Endpoint ---
# Send a sample request to your running service
curl 'http://localhost:3000/api/v1/pricing?period=Summer&hotel=FloatingPointResort&room=SingletonRoom'

# --- 3. Run Tests ---
# Run the full test suite
docker compose exec interview-dev ./bin/rails test

# Run a specific test file
docker compose exec interview-dev ./bin/rails test test/controllers/pricing_controller_test.rb

# Run a specific test by name
docker compose exec interview-dev ./bin/rails test test/controllers/pricing_controller_test.rb -n test_should_get_pricing_with_all_parameters

# --- 4. Run Console ---
# Local environment
cp env.sample .env
./bin/rails console

# Docker environment
docker compose exec interview-dev ./bin/rails console

# --- 5. View Logs ---
docker compose logs -f interview-dev

# --- 6. Access Redis CLI (Docker) ---
docker exec -it dynamic_pricing-redis-1 redis-cli
```

## Assumptions

* Latency is not a primary concern compared to reducing internal API calls.
* No strict SLA requirements: If the service cannot retrieve fresh data, then better to return error over serving stale / default value.
* Request parameters for internal API (single / array) don't significantly impact the cost of internal API calls.

## Implementation

Due to the high operation cost of internal service, this intermediary service should be able to store (cache) rates data temporarily instead of fetching a new rate for every request. Cached data should also follow the validity constraint (no longer than 5 minutes).

Considerations:

* Redis:
Decided to use Redis because it supports TTL, which allows automatic expiration of stored values. It's also accessible across multiple application instances. Lastly, it allows fast read and write which helps reduce processing time.

* Lock:
Lock is needed to prevent cache stampede when multiple requests attempt to refresh the missing / expired cache data. When lock is already acquired, other concurrent requests would wait until the lock is released or timeout is reached to reduce error response. There's also a flag to mark if values have been recently updated, so other requests won't call the API again after acquiring the lock.

* API Call:
Instead of calling the internal service for each room rate, the service will retrieve all rates in a single request to reduce the number of API calls. A retry mechanism (for 5xx responses) is also implemented to improve success rate.

* Error Handling:
The service returns an error response whenever it is unable to provide a valid rate. This includes cases, such as connection failures and empty rates response from the internal service. For any unexpected server errors (5xx), a generic error message is returned to the requester to avoid exposing internal implementation details.

* Monitoring:
Added logging to help trace issues and see error details. Also added metrics (currently implemented via logs) to track request count, its success / error rate, and cache hits / misses, which could be used for alerting.

## AI Usage

Tools used during development: ChatGPT & Gemini

Usage in workflow:

* Design Discussion
  * Clarified trade-offs between different approaches.
  * Researched suitable Ruby gems & functions.

* Development
  * Assisted in validating syntax and debugging code issues.

* Testing
  * Generated sample unit tests
  * Researched ways to validate desired outcomes.
  * Assisted in creating commands for debugging.

* Documentation
  * Refine wording.

## Further Improvement
* Introduce a grace period (stale while revalidate) where the system can still serve the current cache value while rate refresh is started.
* If internal processing takes a long time, background job can be used to reduce latency.
* As the number of records / rooms increases, retrieving all data may become inefficient. To improve performance and reduce unnecessary cache usage, rate retrieval could be filtered by hotel, so that only recently accessed rates are cached.
* Use configuration instead of hard-coded constants for cache TTL to add flexibility.
