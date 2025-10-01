defmodule Hermes.SSE do
  @moduledoc """
  SSE (Server-Sent Events) connection handling.

  ## Adapter Requirements

  This module requires a Tesla adapter that supports response streaming.
  Pass the adapter via the `:tesla_adapter` option.

  Supported streaming adapters:
  - `{Tesla.Adapter.Finch, name: MyFinch, response: :stream}` (requires Finch supervision)
  - `{Tesla.Adapter.Mint, body_as: :stream}`
  - `{Tesla.Adapter.Gun, body_as: :stream}`

  ## Example

      # In your application supervision tree
      children = [
        {Finch, name: MyFinch}
      ]

      # Connect to SSE endpoint
      Hermes.SSE.connect(
        "http://example.com/sse",
        %{},
        tesla_adapter: {Tesla.Adapter.Finch, name: MyFinch, response: :stream}
      )
  """

  use Hermes.Logging

  alias Hermes.SSE.Parser

  @connection_headers %{
    "accept" => "text/event-stream",
    "cache-control" => "no-cache",
    "connection" => "keep-alive"
  }

  @default_http_opts [
    receive_timeout: :infinity,
    request_timeout: :infinity,
    max_reconnections: 5,
    default_backoff: to_timeout(second: 1),
    max_backoff: to_timeout(second: 15)
  ]

  @retry_opts [:max_reconnections, :default_backoff, :max_backoff]

  @doc """
  Connects to a server-sent event stream.

  ## Parameters

    - `server_url` - the URL of the server to connect to.
    - `headers` - additional headers to send with the request.
    - `opts` - additional options to pass to the HTTP client.

  ## Examples

      iex> Hermes.SSE.connect("http://localhost:4000")
      #Stream<[ref: 1, task: #PID<0.123.0>]>

  """
  @spec connect(String.t(), map(), Keyword.t()) :: Enumerable.t()
  def connect(server_url, headers \\ %{}, opts \\ []) do
    opts = Keyword.merge(@default_http_opts, opts)

    case URI.new(server_url) do
      {:ok, _uri} ->
        headers = headers |> Map.merge(@connection_headers) |> Map.to_list()
        adapter = Keyword.get(opts, :tesla_adapter)
        ref = make_ref()
        task = spawn_stream_task(server_url, headers, adapter, ref, opts)

        Stream.resource(
          fn -> {ref, task} end,
          &process_task_stream/1,
          &shutdown_task/1
        )

      {:error, _} ->
        {:error, :invalid_url}
    end
  end

  defp spawn_stream_task(url, headers, adapter, ref, opts) do
    dest = Keyword.get(opts, :dest, self())
    Task.async(fn -> loop_sse_stream(url, headers, adapter, ref, dest, opts) end)
  end

  defp loop_sse_stream(url, headers, adapter, ref, dest, opts, attempt \\ 1) do
    {retry, _http} = Keyword.split(opts, @retry_opts)
    middleware = Keyword.get(opts, :tesla_middleware, [])

    if attempt <= retry[:max_reconnections] do
      max_backoff = retry[:max_backoff]
      base_backoff = retry[:default_backoff]
      backoff = calculate_reconnect_backoff(attempt, max_backoff, base_backoff)

      case fetch_sse_stream(url, headers, adapter, dest, ref, middleware) do
        :ok ->
          Hermes.Logging.transport_event("sse_reconnect", %{
            reason: "success",
            attempt: attempt,
            max_attempts: retry[:max_reconnections]
          })

          Process.sleep(backoff)
          loop_sse_stream(url, headers, adapter, ref, dest, opts, attempt + 1)

        {:error, reason} ->
          Hermes.Logging.transport_event(
            "sse_reconnect",
            %{
              reason: "error",
              error: inspect(reason),
              attempt: attempt,
              max_attempts: retry[:max_reconnections]
            },
            level: :error
          )

          Process.sleep(backoff + to_timeout(second: 1))
          loop_sse_stream(url, headers, adapter, ref, dest, opts, attempt + 1)
      end
    else
      send(dest, {:chunk, :halted, ref})

      Hermes.Logging.transport_event(
        "sse_max_reconnects",
        %{
          max_attempts: retry[:max_reconnections]
        },
        level: :error
      )
    end
  end

  defp fetch_sse_stream(url, headers, adapter, dest, ref, extra_middleware) do
    if adapter == nil do
      raise ArgumentError, """
      SSE streaming requires a Tesla adapter that supports response streaming.

      Please provide one of the following via the :tesla_adapter option:
      - {Tesla.Adapter.Finch, name: MyFinch, response: :stream}
      - {Tesla.Adapter.Mint, body_as: :stream}
      - {Tesla.Adapter.Gun, body_as: :stream}

      See Hermes.SSE moduledoc for more information.
      """
    end

    middleware = extra_middleware ++ [Tesla.Middleware.SSE]
    client = Tesla.client(middleware, adapter)
    url_string = if is_binary(url), do: url, else: URI.to_string(url)

    case Tesla.get(client, url_string, headers: headers) do
      {:ok, %Tesla.Env{status: status, headers: resp_headers, body: body}} when status == 200 ->
        send(dest, {:chunk, {:status, status}, ref})
        send(dest, {:chunk, {:headers, resp_headers}, ref})

        # Tesla.Middleware.SSE parses the stream and returns a Stream of parsed events
        # Each event is a map with keys like :data, :event, :id, :retry
        # We need to convert these to Hermes.SSE.Event structs
        cond do
          is_struct(body, Stream) or is_function(body) ->
            # Stream each parsed SSE event and convert to our Event format
            # This will block on the stream, which is fine for SSE (long-lived connection)
            try do
              Enum.each(body, fn tesla_event ->
                hermes_event = %Hermes.SSE.Event{
                  id: Map.get(tesla_event, :id),
                  event: Map.get(tesla_event, :event, "message"),
                  data: Map.get(tesla_event, :data, Map.get(tesla_event, "data", "")),
                  retry: Map.get(tesla_event, :retry)
                }

                # Send as parsed event directly (not as binary data)
                send(dest, {:chunk, {:sse_event, hermes_event}, ref})
              end)

              # Stream ended normally
              :ok
            catch
              kind, reason ->
                # Stream error
                {:error, {kind, reason}}
            end

          is_binary(body) ->
            # Fallback for non-streaming response body - parse it ourselves
            send(dest, {:chunk, {:data, body}, ref})
            :ok

          true ->
            # Unknown body type
            {:error, {:unknown_body_type, body}}
        end

      {:ok, %Tesla.Env{status: status, body: body}} ->
        send(dest, {:chunk, {:status, status}, ref})
        # For error responses, body might be a stream - consume it to get the actual error message
        error_body =
          cond do
            is_binary(body) -> body
            is_struct(body, Stream) or is_function(body) -> Enum.join(body, "")
            true -> inspect(body)
          end

        {:error, {:bad_status, status, error_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp calculate_reconnect_backoff(attempt, max, base) do
    min(max, attempt ** 2 * base)
  end

  defp process_task_stream({ref, _task} = state) do
    receive do
      {:chunk, {:data, data}, ^ref} when is_binary(data) ->
        {Parser.run(data), state}

      {:chunk, {:data, %Stream{} = _stream}, ^ref} ->
        # This shouldn't happen - means Tesla.Middleware.SSE wasn't applied properly
        # Just ignore and return empty
        Hermes.Logging.transport_event("sse_unexpected_stream", "Received Stream as data")
        {[], state}

      {:chunk, {:sse_event, event}, ^ref} ->
        # Already parsed event from Tesla.Middleware.SSE
        {[event], state}

      {:chunk, {:status, status}, ^ref} ->
        Hermes.Logging.transport_event("sse_status", status)
        {[], state}

      {:chunk, {:headers, headers}, ^ref} ->
        Hermes.Logging.transport_event("sse_headers", headers)
        {[], state}

      {:chunk, :halted, ^ref} ->
        Hermes.Logging.transport_event("sse_halted", "Transport will be restarted")
        {[{:error, :halted}], state}

      {:chunk, unknown, ^ref} ->
        Hermes.Logging.transport_event("sse_unknown_chunk", unknown)
        {[], state}
    end
  end

  defp shutdown_task({_ref, task}), do: Task.shutdown(task)
end
