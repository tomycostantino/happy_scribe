---
targets: ["*"]
description: "Testing conventions and patterns"
globs: ["test/**/*"]
---

# Testing

## Framework

Minitest (Rails default). No RSpec.

## Structure

```
test/
├── controllers/    # Integration tests (ActionDispatch::IntegrationTest)
├── models/         # Unit tests for ActiveRecord models and POROs
├── jobs/           # Job enqueuing and delegation tests
├── fixtures/       # YAML fixtures and test files
├── test_helpers/   # Shared test helpers
└── test_helper.rb  # Base setup (parallel tests, fixtures, minitest/mock)
```

## Conventions

- Tests run in parallel: `parallelize(workers: :number_of_processors)`
- Use fixtures (not factories) for test data
- Use `Minitest::Mock` for stubbing external services
- Controller tests are integration tests, not unit tests
- Use `sign_in_as(user)` helper from `SessionTestHelper` for authenticated tests

## Patterns

### Mocking external APIs

Stub the API client, not HTTP calls:

```ruby
mock_client = Minitest::Mock.new
mock_client.expect(:create_transcription, response_hash, [Hash])
HappyScribe::Client.stub(:new, mock_client) do
  # test code
end
```

### Job tests

Test that jobs enqueue correctly and delegate to the right model:

```ruby
assert_enqueued_with(job: SomeJob, args: [expected_args]) do
  # trigger action
end
```

### Fixtures

- Fixtures live in `test/fixtures/`
- Test files (e.g. sample.mp3) live in `test/fixtures/files/`
- Reference fixtures by name: `meetings(:one)`, `users(:one)`
