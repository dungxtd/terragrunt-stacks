locals {
  # Set to true to route all AWS API calls to MiniStack (http://localhost:4566)
  use_ministack = true

  ministack_endpoint = "http://localhost:4566"

  # MiniStack credentials (any value works)
  ministack_access_key = "test"
  ministack_secret_key = "test"
}
