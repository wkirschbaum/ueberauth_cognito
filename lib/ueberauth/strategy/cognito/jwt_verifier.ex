defmodule Ueberauth.Strategy.Cognito.JwtVerifier do
  @moduledoc """
  Utilities for working with JSON Web Tokens
  """

  alias Ueberauth.Strategy.Cognito.Utilities

  @doc "Verifies that a JWT is a valid id token: the signature is correct,
  the audience is the AWS `client_id`, the issuer is the user pool,
  and it has not expired"
  def verify(jwt, jwks, config) do
    with {:ok, claims_json} <- verified_claims(jwks, jwt),
         {:ok, claims} <- Jason.decode(claims_json),
         true <- claims["aud"] == config.client_id,
         true <- is_number(claims["exp"]) and claims["exp"] > System.system_time(:second),
         true <- claims["iss"] == Utilities.jwk_url_prefix(config),
         true <- claims["token_use"] == "id" do
      {:ok, claims}
    else
      _ ->
        {:error, :invalid_jwt}
    end
  end

  defp verified_claims(%{"keys" => keys}, jwt) when is_list(keys) do
    keys
    |> Enum.map(&JOSE.JWK.from(&1))
    |> Enum.find_value(fn jwk ->
      case JOSE.JWS.verify_strict(jwk, ["RS256"], jwt) do
        {true, claims_json, _} -> {:ok, claims_json}
        _ -> nil
      end
    end)
  end

  defp verified_claims(_jwks, _jwt), do: nil
end
