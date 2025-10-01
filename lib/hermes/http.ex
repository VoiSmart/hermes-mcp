defmodule Hermes.HTTP do
  @moduledoc false

  use Hermes.Logging

  @default_headers %{
    "content-type" => "application/json"
  }

  @max_redirects 3

  def build(method, url, headers \\ %{}, body \\ nil, opts \\ []) do
    case URI.new(url) do
      {:ok, _uri} ->
        headers = @default_headers |> Map.merge(headers) |> Map.to_list()
        tesla_adapter = Keyword.get(opts, :tesla_adapter)
        extra_middleware = Keyword.get(opts, :tesla_middleware, [])

        middleware =
          extra_middleware ++
            [
              {Tesla.Middleware.Headers, headers},
              {Tesla.Middleware.FollowRedirects, max_redirects: @max_redirects}
            ]

        client = Tesla.client(middleware, tesla_adapter)
        {:ok, {client, method, url, body}}

      {:error, _} ->
        {:error, :invalid_url}
    end
  end

  @doc """
  Performs a POST request to the given URL.
  """
  def post(url, headers \\ %{}, body \\ nil) do
    headers = Map.merge(@default_headers, headers)
    build(:post, url, headers, body)
  end

  def request({client, method, url, body}) do
    Tesla.request(client, method: method, url: url, body: body)
  end
end
