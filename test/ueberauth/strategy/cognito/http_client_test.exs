defmodule Ueberauth.Strategy.Cognito.HttpClientTest do
  @moduledoc """
  Exercises the real Mint-based client against a local TCP server, so the
  request path the strategy uses in production has coverage the strategy
  tests (which stub the client out) cannot provide.
  """

  use ExUnit.Case

  alias Ueberauth.Strategy.Cognito.HttpClient

  test "GET returns status, headers and body, sending the path and query" do
    body = ~s({"keys":[]})

    {port, server} =
      serve(fn socket, request ->
        respond(socket, "HTTP/1.1 200 OK", [{"content-type", "application/json"}], body)
        request
      end)

    assert {:ok, 200, headers, ^body} =
             HttpClient.request(:get, "http://127.0.0.1:#{port}/.well-known/jwks.json?v=1")

    assert {"content-type", "application/json"} in headers
    assert Task.await(server) =~ "GET /.well-known/jwks.json?v=1 HTTP/1.1"
  end

  test "POST sends headers and body" do
    {port, server} =
      serve(fn socket, request ->
        request = request <> read_until(socket, request, "grant_type=code")
        respond(socket, "HTTP/1.1 200 OK", [], ~s({"ok":true}))
        request
      end)

    assert {:ok, 200, _headers, ~s({"ok":true})} =
             HttpClient.request(
               :post,
               "http://127.0.0.1:#{port}/oauth2/token",
               [{"content-type", "application/x-www-form-urlencoded"}],
               "grant_type=code"
             )

    request = Task.await(server)
    assert request =~ "POST /oauth2/token HTTP/1.1"
    assert request =~ "content-type: application/x-www-form-urlencoded"
    assert request =~ "grant_type=code"
  end

  test "non-200 responses are returned with their status" do
    {port, _server} =
      serve(fn socket, request ->
        respond(socket, "HTTP/1.1 403 Forbidden", [], "denied")
        request
      end)

    assert {:ok, 403, _headers, "denied"} = HttpClient.request(:get, "http://127.0.0.1:#{port}/")
  end

  test "a complete response followed by protocol garbage in the same packet is not lost" do
    {port, _server} =
      serve(fn socket, request ->
        # response and trailing garbage arrive in one TCP segment, so Mint
        # reports the parse error and the finished response in the same recv
        :gen_tcp.send(
          socket,
          "HTTP/1.1 200 OK\r\ncontent-length: 2\r\n\r\nokGARBAGE AFTER RESPONSE"
        )

        request
      end)

    assert {:ok, 200, _headers, "ok"} = HttpClient.request(:get, "http://127.0.0.1:#{port}/")
  end

  test "a slow-dripping response hits the overall deadline instead of looping forever" do
    Application.put_env(:ueberauth_cognito, :request_timeout, 400)
    on_exit(fn -> Application.delete_env(:ueberauth_cognito, :request_timeout) end)

    {port, _server} =
      serve(fn socket, request ->
        :gen_tcp.send(socket, "HTTP/1.1 200 OK\r\ntransfer-encoding: chunked\r\n\r\n")
        drip(socket)
        request
      end)

    started = System.monotonic_time(:millisecond)

    # the deadline surfaces as :timeout when it expires between recvs, or as
    # Mint's transport timeout when the final bounded recv runs out of time
    assert {:error, reason} = HttpClient.request(:get, "http://127.0.0.1:#{port}/")
    assert reason == :timeout or reason == %Mint.TransportError{reason: :timeout}
    assert System.monotonic_time(:millisecond) - started < 2_000
  end

  test "connection errors are returned as error tuples" do
    {:ok, listen} = :gen_tcp.listen(0, [:binary])
    {:ok, port} = :inet.port(listen)
    :gen_tcp.close(listen)

    assert {:error, %Mint.TransportError{}} =
             HttpClient.request(:get, "http://127.0.0.1:#{port}/")
  end

  test "unsupported URL schemes are returned as error tuples" do
    assert {:error, {:unsupported_scheme, "ftp"}} = HttpClient.request(:get, "ftp://example.com/")
  end

  # Starts a one-request server; the responder receives the socket and the
  # request head (through the blank line) and returns what it read, which
  # serve/1 hands back through the task for assertions.
  defp serve(responder) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listen, 5_000)
        request = read_until(socket, "", "\r\n\r\n")
        result = responder.(socket, request)
        :gen_tcp.close(socket)
        :gen_tcp.close(listen)
        result
      end)

    {port, server}
  end

  defp read_until(socket, acc, marker) do
    if String.contains?(acc, marker) do
      acc
    else
      {:ok, data} = :gen_tcp.recv(socket, 0, 5_000)
      read_until(socket, acc <> data, marker)
    end
  end

  defp respond(socket, status_line, headers, body) do
    header_lines = Enum.map(headers, fn {name, value} -> "#{name}: #{value}\r\n" end)

    :gen_tcp.send(socket, [
      status_line,
      "\r\ncontent-length: #{byte_size(body)}\r\n",
      header_lines,
      "\r\n",
      body
    ])
  end

  defp drip(socket) do
    case :gen_tcp.send(socket, "3\r\nabc\r\n") do
      :ok ->
        Process.sleep(100)
        drip(socket)

      {:error, _} ->
        :ok
    end
  end
end
