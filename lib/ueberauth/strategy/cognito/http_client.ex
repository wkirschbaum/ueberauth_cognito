defmodule Ueberauth.Strategy.Cognito.HttpClient do
  @moduledoc """
  Minimal Mint-based HTTP client used by the Cognito strategy.

  Implements the strategy's `http_client` contract: `request/2` and
  `request/4` return `{:ok, status, headers, body}` on a completed
  response, or `{:error, reason}`.
  """

  @recv_timeout 30_000

  def request(method, url), do: request(method, url, [], "")

  def request(method, url, headers, body) do
    uri = URI.parse(url)

    with {:ok, scheme} <- scheme(uri),
         {:ok, conn} <- Mint.HTTP.connect(scheme, uri.host, uri.port, mode: :passive) do
      case Mint.HTTP.request(conn, method_string(method), request_target(uri), headers, body) do
        {:ok, conn, ref} ->
          recv_response(conn, ref, nil, [], [])

        {:error, conn, reason} ->
          Mint.HTTP.close(conn)
          {:error, reason}
      end
    end
  end

  defp scheme(%URI{scheme: "https"}), do: {:ok, :https}
  defp scheme(%URI{scheme: "http"}), do: {:ok, :http}
  defp scheme(%URI{scheme: scheme}), do: {:error, {:unsupported_scheme, scheme}}

  defp method_string(method), do: method |> to_string() |> String.upcase()

  defp request_target(%URI{path: path, query: query}) do
    target = if path in [nil, ""], do: "/", else: path
    if query, do: target <> "?" <> query, else: target
  end

  defp recv_response(conn, ref, status, headers, body_acc) do
    case Mint.HTTP.recv(conn, 0, @recv_timeout) do
      {:ok, conn, entries} ->
        case handle_entries(entries, ref, status, headers, body_acc) do
          {:cont, status, headers, body_acc} ->
            recv_response(conn, ref, status, headers, body_acc)

          result ->
            Mint.HTTP.close(conn)
            result
        end

      {:error, conn, reason, _entries} ->
        Mint.HTTP.close(conn)
        {:error, reason}
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
end
