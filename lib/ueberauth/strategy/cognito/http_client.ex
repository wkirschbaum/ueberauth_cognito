defmodule Ueberauth.Strategy.Cognito.HttpClient do
  @moduledoc """
  Minimal Mint-based HTTP client used by the Cognito strategy.

  Defines the strategy's `http_client` contract as a behaviour and is
  its default implementation: `request/2` and `request/4` return
  `{:ok, status, headers, body}` on a completed response, or
  `{:error, reason}`.

  The whole request — connecting included — is bounded by an overall
  deadline, 30 seconds by default:

      config :ueberauth_cognito, request_timeout: 10_000
  """

  @type status :: non_neg_integer()
  @type headers :: [{binary(), binary()}]
  @type response :: {:ok, status(), headers(), binary()} | {:error, term()}

  @callback request(method :: atom(), url :: binary()) :: response()
  @callback request(method :: atom(), url :: binary(), headers(), body :: iodata()) ::
              response()

  @behaviour __MODULE__

  @default_request_timeout 30_000

  @impl __MODULE__
  def request(method, url), do: request(method, url, [], "")

  @impl __MODULE__
  def request(method, url, headers, body) do
    uri = URI.parse(url)
    deadline = System.monotonic_time(:millisecond) + request_timeout()

    with {:ok, scheme} <- scheme(uri),
         {:ok, conn} <- connect(scheme, uri, deadline) do
      case Mint.HTTP.request(conn, method_string(method), request_target(uri), headers, body) do
        {:ok, conn, ref} ->
          recv_response(conn, ref, deadline, nil, [], [])

        {:error, conn, reason} ->
          Mint.HTTP.close(conn)
          {:error, reason}
      end
    end
  end

  defp request_timeout do
    Application.get_env(:ueberauth_cognito, :request_timeout, @default_request_timeout)
  end

  defp connect(scheme, uri, deadline) do
    Mint.HTTP.connect(scheme, uri.host, uri.port,
      mode: :passive,
      transport_opts: [timeout: remaining(deadline)],
      client_settings: [enable_push: false]
    )
  end

  defp scheme(%URI{scheme: "https"}), do: {:ok, :https}
  defp scheme(%URI{scheme: "http"}), do: {:ok, :http}
  defp scheme(%URI{scheme: scheme}), do: {:error, {:unsupported_scheme, scheme}}

  defp method_string(method), do: method |> to_string() |> String.upcase()

  defp request_target(%URI{} = uri) do
    path = if uri.path in [nil, ""], do: "/", else: uri.path
    URI.to_string(%URI{path: path, query: uri.query})
  end

  defp remaining(deadline) do
    max(deadline - System.monotonic_time(:millisecond), 0)
  end

  defp recv_response(conn, ref, deadline, status, headers, body_acc) do
    case remaining(deadline) do
      0 ->
        Mint.HTTP.close(conn)
        {:error, :timeout}

      remaining ->
        case Mint.HTTP.recv(conn, 0, remaining) do
          {:ok, conn, entries} ->
            case handle_entries(entries, ref, status, headers, body_acc) do
              {:cont, status, headers, body_acc} ->
                recv_response(conn, ref, deadline, status, headers, body_acc)

              result ->
                Mint.HTTP.close(conn)
                result
            end

          {:error, conn, reason, entries} ->
            # the same recv can deliver a complete response together with a
            # connection-level error (e.g. an HTTP/2 GOAWAY, or trailing
            # bytes after a finished HTTP/1.1 body) — don't lose the response
            Mint.HTTP.close(conn)

            case handle_entries(entries, ref, status, headers, body_acc) do
              {:ok, _, _, _} = response -> response
              _ -> {:error, reason}
            end
        end
    end
  end

  defp handle_entries([], _ref, status, headers, body_acc) do
    {:cont, status, headers, body_acc}
  end

  defp handle_entries([{:status, ref, status} | rest], ref, _status, headers, body_acc) do
    handle_entries(rest, ref, status, headers, body_acc)
  end

  defp handle_entries([{:headers, ref, new_headers} | rest], ref, status, headers, body_acc) do
    handle_entries(rest, ref, status, headers ++ new_headers, body_acc)
  end

  defp handle_entries([{:data, ref, data} | rest], ref, status, headers, body_acc) do
    handle_entries(rest, ref, status, headers, [body_acc, data])
  end

  defp handle_entries([{:done, ref} | _rest], ref, status, headers, body_acc) do
    {:ok, status, headers, IO.iodata_to_binary(body_acc)}
  end

  defp handle_entries([{:error, ref, reason} | _rest], ref, _status, _headers, _body_acc) do
    {:error, reason}
  end

  # entries for other refs or of unknown kinds (e.g. server-push streams,
  # which we disable but a server could still initiate) are ignored
  defp handle_entries([_other | rest], ref, status, headers, body_acc) do
    handle_entries(rest, ref, status, headers, body_acc)
  end
end
