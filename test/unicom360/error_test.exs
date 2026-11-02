defmodule Unicom360.ErrorTest do
  use ExUnit.Case, async: true
  doctest Unicom360.Error

  alias Unicom360.Error

  test "every type has a class" do
    for {type, class} <- [
          unicom360_error: "Unicom360Error",
          configuration_error: "ConfigurationError",
          connection_error: "APIConnectionError",
          timeout_error: "APITimeoutError",
          api_status_error: "APIStatusError",
          authentication_error: "AuthenticationError",
          rate_limit_error: "RateLimitError",
          invalid_request_error: "InvalidRequestError",
          api_server_error: "APIServerError",
          api_error: "APIError",
          signature_verification_error: "SignatureVerificationError"
        ] do
      assert Error.class(%Error{type: type}) == class
    end
  end

  test "an API error is classed by its code" do
    for {code, class} <- [
          {"INSUFFICIENT_BUNDLE", "InsufficientBundleError"},
          {"DUPLICATE_REFERENCE", "DuplicateReferenceError"},
          {"NO_VALID_RECIPIENTS", "NoValidRecipientsError"},
          {"SESSION_WINDOW_CLOSED", "SessionWindowClosedError"},
          {"INVALID_SENDER_ID", "APIError"},
          {nil, "APIError"}
        ] do
      assert Error.class(%Error{type: :api_error, code: code}) == class
    end
  end

  test "the exception message adds the reference to quote to support" do
    assert Exception.message(%Error{message: "Nope"}) == "Nope"

    assert Exception.message(%Error{message: "Nope", api_reference: "r"}) ==
             "Nope (api_reference r)"
  end

  test "family checks" do
    assert Error.connection_error?(%Error{type: :timeout_error})
    assert Error.connection_error?(%Error{type: :connection_error})
    refute Error.connection_error?(%Error{type: :api_error})
    assert Error.status_error?(%Error{type: :rate_limit_error})
    refute Error.status_error?(%Error{type: :api_error})
  end

  test "it is raisable" do
    assert_raise Error, "Nope", fn -> raise %Error{message: "Nope"} end
  end
end
