# The Ueberauth plug reads its provider list when the router module is
# compiled, so this env must be set before the module is defined.
Application.put_env(:ueberauth, Ueberauth, providers: [cognito: {Ueberauth.Strategy.Cognito, []}])

defmodule Ueberauth.Strategy.Cognito.IntegrationTest do
  @moduledoc """
  Drives the full auth flow through the Ueberauth plug: request phase,
  CSRF state cookie round-trip, callback phase, and real JWT verification
  with an RSA-signed id token.
  """

  use ExUnit.Case
  use Plug.Test

  defmodule FakeHackney do
    def request(:post, "https://testdomain.com/oauth2/token", _headers, _body) do
      {:ok, 200, [], Application.get_env(:ueberauth_cognito_test, :token_body)}
    end

    def request(:get, "https://cognito-idp" <> _) do
      {:ok, 200, [], Application.get_env(:ueberauth_cognito_test, :jwks_body)}
    end
  end

  defmodule Router do
    use Plug.Router

    plug(:fetch_query_params)
    plug(:fetch_cookies)
    plug(Ueberauth)
    plug(:match)
    plug(:dispatch)

    get "/auth/cognito/callback" do
      cond do
        conn.assigns[:ueberauth_auth] -> send_resp(conn, 200, "welcome")
        conn.assigns[:ueberauth_failure] -> send_resp(conn, 401, "failure")
        true -> send_resp(conn, 500, "no result")
      end
    end

    match _ do
      send_resp(conn, 404, "not found")
    end
  end

  @client_id "integration_client_id"
  @user_pool_id "integration_pool"
  @aws_region "eu-west-1"

  setup do
    Application.put_env(:ueberauth, Ueberauth.Strategy.Cognito, %{
      auth_domain: "testdomain.com",
      client_id: @client_id,
      client_secret: "integration_secret",
      user_pool_id: @user_pool_id,
      aws_region: @aws_region
    })

    Application.put_env(:ueberauth_cognito, :__http_client, FakeHackney)

    Application.put_env(
      :ueberauth_cognito,
      :__jwt_verifier,
      Ueberauth.Strategy.Cognito.JwtVerifier
    )

    jwk = JOSE.JWK.generate_key({:rsa, 1024})
    stub_aws_responses(jwk, valid_claims())

    {:ok, jwk: jwk}
  end

  test "authenticates through the full request and callback flow" do
    request_conn =
      conn(:get, "/auth/cognito")
      |> init_test_session(%{})
      |> Router.call(Router.init([]))

    assert request_conn.status == 302
    {"location", location} = List.keyfind(request_conn.resp_headers, "location", 0)

    authorize_url = URI.parse(location)
    assert authorize_url.host == "testdomain.com"
    assert authorize_url.path == "/oauth2/authorize"

    query = URI.decode_query(authorize_url.query)
    assert query["client_id"] == @client_id
    assert query["response_type"] == "code"
    assert query["redirect_uri"] == "http://www.example.com/auth/cognito/callback"
    assert %{"state" => state} = query

    callback_conn =
      conn(:get, "/auth/cognito/callback", %{"code" => "the_code", "state" => state})
      |> recycle_cookies(request_conn)
      |> init_test_session(%{})
      |> Router.call(Router.init([]))

    assert callback_conn.status == 200

    auth = callback_conn.assigns.ueberauth_auth
    assert %Ueberauth.Auth{} = auth
    assert auth.uid == "integration_user"
    assert auth.provider == :cognito
    assert auth.credentials.token == "the_access_token"
    assert auth.credentials.refresh_token == "the_refresh_token"
    assert auth.credentials.expires
    assert auth.credentials.other.groups == ["admins"]
    assert auth.info.email == "user@example.com"
  end

  test "rejects an id token signed with the wrong key", %{jwk: jwk} do
    attacker_jwk = JOSE.JWK.generate_key({:rsa, 1024})
    stub_aws_responses(jwk, valid_claims(), signing_jwk: attacker_jwk)

    callback_conn = authenticate_with_state()

    assert callback_conn.status == 401

    assert [%Ueberauth.Failure.Error{message_key: "bad_id_token"}] =
             callback_conn.assigns.ueberauth_failure.errors
  end

  test "rejects an expired id token", %{jwk: jwk} do
    stub_aws_responses(jwk, %{valid_claims() | "exp" => System.system_time(:second) - 60})

    callback_conn = authenticate_with_state()

    assert callback_conn.status == 401

    assert [%Ueberauth.Failure.Error{message_key: "bad_id_token"}] =
             callback_conn.assigns.ueberauth_failure.errors
  end

  test "rejects a callback with a wrong CSRF state" do
    request_conn =
      conn(:get, "/auth/cognito")
      |> init_test_session(%{})
      |> Router.call(Router.init([]))

    callback_conn =
      conn(:get, "/auth/cognito/callback", %{"code" => "the_code", "state" => "forged"})
      |> recycle_cookies(request_conn)
      |> init_test_session(%{})
      |> Router.call(Router.init([]))

    assert callback_conn.status == 401

    assert [%Ueberauth.Failure.Error{message_key: "csrf_attack"}] =
             callback_conn.assigns.ueberauth_failure.errors
  end

  test "reports an OAuth error callback from Cognito" do
    request_conn =
      conn(:get, "/auth/cognito")
      |> init_test_session(%{})
      |> Router.call(Router.init([]))

    {"location", location} = List.keyfind(request_conn.resp_headers, "location", 0)
    %{"state" => state} = URI.decode_query(URI.parse(location).query)

    callback_conn =
      conn(:get, "/auth/cognito/callback", %{"error" => "access_denied", "state" => state})
      |> recycle_cookies(request_conn)
      |> init_test_session(%{})
      |> Router.call(Router.init([]))

    assert callback_conn.status == 401

    assert [%Ueberauth.Failure.Error{message_key: "access_denied"}] =
             callback_conn.assigns.ueberauth_failure.errors
  end

  defp authenticate_with_state do
    request_conn =
      conn(:get, "/auth/cognito")
      |> init_test_session(%{})
      |> Router.call(Router.init([]))

    {"location", location} = List.keyfind(request_conn.resp_headers, "location", 0)
    %{"state" => state} = URI.decode_query(URI.parse(location).query)

    conn(:get, "/auth/cognito/callback", %{"code" => "the_code", "state" => state})
    |> recycle_cookies(request_conn)
    |> init_test_session(%{})
    |> Router.call(Router.init([]))
  end

  defp valid_claims do
    %{
      "iss" => "https://cognito-idp.#{@aws_region}.amazonaws.com/#{@user_pool_id}",
      "aud" => @client_id,
      "exp" => System.system_time(:second) + 300,
      "token_use" => "id",
      "cognito:username" => "integration_user",
      "cognito:groups" => ["admins"],
      "email" => "user@example.com"
    }
  end

  defp stub_aws_responses(jwk, claims, opts \\ []) do
    signing_jwk = Keyword.get(opts, :signing_jwk, jwk)

    {_meta, id_token} =
      JOSE.JWT.sign(signing_jwk, %{"alg" => "RS256"}, claims)
      |> JOSE.JWS.compact()

    token_body =
      Jason.encode!(%{
        "access_token" => "the_access_token",
        "id_token" => id_token,
        "refresh_token" => "the_refresh_token",
        "expires_in" => 3600
      })

    {_meta, public_jwk} = jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
    jwks_body = Jason.encode!(%{"keys" => [public_jwk]})

    Application.put_env(:ueberauth_cognito_test, :token_body, token_body)
    Application.put_env(:ueberauth_cognito_test, :jwks_body, jwks_body)
  end
end
