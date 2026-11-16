defmodule PayPalAPIJSONTest do
  # Pins the JSON PayPal.API sends and the terms it returns, for each branch that encodes or
  # decodes. HTTPoison is replaced with :meck, which is global, so this module is not async.
  use ExUnit.Case, async: false

  setup do
    :meck.new(HTTPoison, [:passthrough, :no_link])
    on_exit(fn -> :meck.unload(HTTPoison) end)
  end

  # Answers the next `fun` request with `status` and `body`, and sends the request body it got
  # back to the test process.
  defp respond(:get, status, body) do
    :meck.expect(HTTPoison, :get, fn _url, _headers -> reply(status, body) end)
  end

  defp respond(fun, status, body) do
    test_pid = self()

    :meck.expect(HTTPoison, fun, fn _url, sent, _headers ->
      send(test_pid, {:sent, sent})
      reply(status, body)
    end)

    :meck.expect(HTTPoison, fun, fn _url, sent, _headers, _options ->
      send(test_pid, {:sent, sent})
      reply(status, body)
    end)
  end

  defp reply(status, body), do: {:ok, %HTTPoison.Response{status_code: status, body: body}}

  defp sent_body do
    assert_received {:sent, body}
    body
  end

  @payload %{
    description: "Doofinder",
    payer: %{payment_method: "paypal"},
    note: "Müller € 😀 \"q\" / \\ \n",
    plan: %{
      type: "MERCHANT_INITIATED_BILLING",
      merchant_preferences: %{
        return_url: "https://example.com/ok?a=1&b=2",
        skip_shipping_address: true,
        max_fail_attempts: 3,
        setup_fee: nil
      }
    },
    transactions: [%{amount: %{currency: "EUR", total: "49.99"}}]
  }

  @payload_json %{
    "description" => "Doofinder",
    "payer" => %{"payment_method" => "paypal"},
    "note" => "Müller € 😀 \"q\" / \\ \n",
    "plan" => %{
      "type" => "MERCHANT_INITIATED_BILLING",
      "merchant_preferences" => %{
        "return_url" => "https://example.com/ok?a=1&b=2",
        "skip_shipping_address" => true,
        "max_fail_attempts" => 3,
        "setup_fee" => nil
      }
    },
    "transactions" => [%{"amount" => %{"currency" => "EUR", "total" => "49.99"}}]
  }

  @response ~s({"id":"PAY-1","state":"approved","count":2,"fee":1.95,"note":null,"ok":true,) <>
              ~s("name":"Müller \\u00e9 \\ud83d\\ude00","transactions":[{"related_resources":[{"sale":{"id":"5X"}}]}],) <>
              ~s("links":[{"href":"https://x/y?a=1&b=2","rel":"approval_url"}]})

  @decoded %{
    id: "PAY-1",
    state: "approved",
    count: 2,
    fee: 1.95,
    note: nil,
    ok: true,
    name: "Müller é 😀",
    transactions: [%{related_resources: [%{sale: %{id: "5X"}}]}],
    links: [%{href: "https://x/y?a=1&b=2", rel: "approval_url"}]
  }

  @error ~s({"name":"VALIDATION_ERROR","message":"Invalid request","details":[{"field":"payer","issue":"Required"}]})

  @decoded_error %{
    name: "VALIDATION_ERROR",
    message: "Invalid request",
    details: [%{field: "payer", issue: "Required"}]
  }

  describe "post/2" do
    test "sends the payload as JSON" do
      respond(:post, 201, @response)
      PayPal.API.post("payments/payment", @payload)
      assert Jason.decode!(sent_body()) == @payload_json
    end

    test "sends a nil payload as JSON null" do
      respond(:post, 204, "")
      assert PayPal.API.post("payments/payment/1/execute", nil) == {:ok, nil}
      assert sent_body() == "null"
    end

    test "sends an empty payload as an empty object" do
      respond(:post, 204, "")
      PayPal.API.post("billing-agreements/agreements/1/cancel", %{})
      assert sent_body() == "{}"
    end

    test "decodes a 200 body with atom keys" do
      respond(:post, 200, @response)
      assert PayPal.API.post("payments/payment", @payload) == {:ok, @decoded}
    end

    test "decodes a 201 body with atom keys" do
      respond(:post, 201, @response)
      assert PayPal.API.post("payments/payment", @payload) == {:ok, @decoded}
    end

    test "decodes a 400 body into the error" do
      respond(:post, 400, @error)
      assert PayPal.API.post("payments/payment", @payload) == {:error, @decoded_error}
    end

    test "raises on a body that is not JSON" do
      respond(:post, 200, "<html>Bad gateway</html>")
      assert %_{} = catch_error(PayPal.API.post("payments/payment", @payload))
    end
  end

  describe "get/1" do
    test "decodes a 200 body with atom keys" do
      respond(:get, 200, @response)
      assert PayPal.API.get("payments/payment/PAY-1") == {:ok, @decoded}
    end

    test "decodes a 400 body into the error" do
      respond(:get, 400, @error)
      assert PayPal.API.get("payments/payment/PAY-1") == {:error, @decoded_error}
    end
  end

  describe "patch/2" do
    test "sends the payload as JSON" do
      respond(:patch, 200, "")
      assert PayPal.API.patch("payments/payment/PAY-1", @payload) == {:ok, nil}
      assert Jason.decode!(sent_body()) == @payload_json
    end

    test "sends a list payload as a JSON array" do
      respond(:patch, 200, "")
      changes = [%{op: "replace", path: "/", value: %{state: "ACTIVE"}}]
      PayPal.API.patch("payments/billing-plans/P-1", changes)

      assert Jason.decode!(sent_body()) == [
               %{"op" => "replace", "path" => "/", "value" => %{"state" => "ACTIVE"}}
             ]
    end

    test "decodes a 201 body with atom keys" do
      respond(:patch, 201, @response)
      assert PayPal.API.patch("payments/payment/PAY-1", @payload) == {:ok, @decoded}
    end

    test "decodes a 400 body into the error" do
      respond(:patch, 400, @error)
      assert PayPal.API.patch("payments/payment/PAY-1", @payload) == {:error, @decoded_error}
    end
  end

  describe "get_oauth_token/0" do
    test "decodes the token and its lifetime" do
      respond(
        :post,
        200,
        ~s({"scope":"https://uri.paypal.com/services/x","access_token":"A21AA","token_type":"Bearer","expires_in":32400})
      )

      assert PayPal.API.get_oauth_token() == {:ok, {"A21AA", 32400}}
    end
  end
end
