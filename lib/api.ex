defmodule PayPal.API do
  @moduledoc """
  Documentation for PayPal.API. This module is about the base HTTP functionality
  """
  @base_url_sandbox "https://api.sandbox.paypal.com/v1/"
  @base_url_live "https://api.paypal.com/v1/"

  @doc """
  Requests an OAuth token from PayPal, returns a tuple containing the token and seconds till expiry.

  Note: If your name is not Zen and you're reading this, unless you're sending me a PR (thanks!), you probably don't need this.

  Possible returns:

  - {:ok, {"XXXXXXXXXXXXXX", 32000}}
  - {:error, :unauthorised}
  - {:error, reason}
  - {:error, :bad_network}

  ## Examples

    iex> PayPal.API.get_oauth_token
    {:ok, {"XXXXXXXXXXXXXX", 32000}}

  """
  @spec get_oauth_token :: {:error, :unauthorised | :bad_network | map} | {:ok, {binary, integer}}
  def get_oauth_token do
    headers = %{"Content-Type" => "application/x-www-form-urlencoded"}
    options = [hackney: [basic_auth: {PayPal.Config.get.client_id, PayPal.Config.get.client_secret}]]
    form = {:form, [grant_type: "client_credentials"]}

    case HTTPoison.post(base_url() <> "oauth2/token", form, headers, options) do
      {:ok, %{status_code: 401}} ->
        {:error, :unauthorised}
      {:ok, %{body: body, status_code: 200}} ->
        %{access_token: access_token, expires_in: expires_in} = Jason.decode!(body, keys: :atoms)
        {:ok, {access_token, expires_in}}
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
      _->
        {:error, :bad_network}
    end
  end

  @doc """
  Make a HTTP GET request to the correct API depending on environment, adding needed auth header.

  Note: If your name is not Zen and you're reading this, unless you're sending me a PR (thanks!), you probably don't need this.

  Possible returns:

  - {:ok, data}
  - {:ok, :not_found}
  - {:ok, :no_content}
  - {:error, :unauthorised}
  - {:error, :bad_network}
  - {:error, reason}

  ## Examples

    iex> PayPal.API.get(url)
    {:ok, {"XXXXXXXXXXXXXX", 32000}}

  """
  @spec get(String.t) :: {:ok, map | :not_found | :no_content } | {:error, :unauthorised | :bad_network | any}
  def get(url) do
    case HTTPoison.get(base_url() <> url, headers()) do
      {:ok, %{status_code: 401}} ->
        {:error, :unauthorised}
      {:ok, %{body: body, status_code: 200}} ->
        {:ok, Jason.decode!(body, keys: :atoms)}
      {:ok, %{status_code: 404}} ->
        {:ok, :not_found}
      {:ok, %{body: body, status_code: 400}} ->
        {:error, Jason.decode!(body, keys: :atoms)}
      {:ok, %{status_code: 204}} ->
        {:ok, :no_content}
      {:ok, %{body: body}}->
        {:error, body}
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error,  reason}
      _ ->
        {:error, :bad_network}
    end
  end

  @doc """
  Make a HTTP POST request to the correct API depending on environment, adding needed auth header.

  Note: If your name is not Zen and you're reading this, unless you're sending me a PR (thanks!), you probably don't need this.

  Possible returns:

  - {:ok, data}
  - {:ok, :not_found}
  - {:ok, :no_content}
  - {:error, :unauthorised}
  - {:error, :bad_network}
  - {:error, reason}

  ## Examples

    iex> PayPal.API.post(url, data)
    {:ok, {"XXXXXXXXXXXXXX", 32000}}

  """
  @spec post(String.t, map | list | nil) :: {:ok, map | :not_found | :no_content | nil} | {:error, :unauthorised | :bad_network | any}
  def post(url, data) do
    {:ok, data} = Jason.encode(data)
    case HTTPoison.post(base_url() <> url, data, headers()) do
      {:ok, %{status_code: 401}} ->
        {:error, :unauthorised}
      {:ok, %{body: body, status_code: 200}} ->
        {:ok, Jason.decode!(body, keys: :atoms)}
      {:ok, %{body: body, status_code: 201}} ->
        {:ok, Jason.decode!(body, keys: :atoms)}
      {:ok, %{status_code: 404}} ->
        {:ok, :not_found}
      {:ok, %{status_code: 204}} ->
        {:ok, nil}
      {:ok, %{body: body, status_code: 400}} ->
        {:error, Jason.decode!(body, keys: :atoms)}
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
      _ ->
        {:error, :bad_network}
    end
  end

  @doc """
  Make a HTTP PATCH request to the correct API depending on environment, adding needed auth header.

  Note: If your name is not Zen and you're reading this, unless you're sending me a PR (thanks!), you probably don't need this.

  Possible returns:

  - {:ok, data}
  - {:ok, :not_found}
  - {:ok, :no_content}
  - {:error, :unauthorised}
  - {:error, :bad_network}

  ## Examples

    iex> PayPal.API.patch(url, data)
    {:ok, {"XXXXXXXXXXXXXX", 32000}}

  """
  @spec patch(String.t, map | list) :: {:ok, map | nil | :not_found | :no_content} | {:error, :unauthorised | :bad_network | any}
  def patch(url, data) do
    {:ok, data} = Jason.encode(data)
    case HTTPoison.patch(base_url() <> url, data, headers()) do
      {:ok, %{status_code: 401}} ->
        {:error, :unauthorised}
      {:ok, %{status_code: 200}} ->
        {:ok, nil}
      {:ok, %{body: body, status_code: 201}} ->
        {:ok, Jason.decode!(body, keys: :atoms)}
      {:ok, %{status_code: 404}} ->
        {:ok, :not_found}
      {:ok, %{status_code: 204}} ->
        {:ok, :no_content}
      {:ok, %{body: body, status_code: 400}} ->
        {:error, Jason.decode!(body, keys: :atoms)}
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
      _ ->
        {:error, :unknown_error}
    end
  end

  @spec headers :: map
  defp headers do
    %{"Authorization" => "Bearer #{Application.get_env(:pay_pal, :access_token)}", "Content-Type" => "application/json"}
  end

  @spec base_url :: String.t
  defp base_url do
    case Application.get_env(:pay_pal, :environment) do
      :sandbox -> @base_url_sandbox
      :live -> @base_url_live
      :prod -> @base_url_live
      _ ->
        require Logger
        Logger.warning "[PayPal] No `env` found in config, use `sandbox` as default."
        @base_url_sandbox
    end
  end
end
