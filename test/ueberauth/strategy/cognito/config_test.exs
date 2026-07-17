defmodule Ueberauth.Strategy.Cognito.ConfigTest do
  use ExUnit.Case
  use Plug.Test

  alias Ueberauth.Strategy.Cognito.Config

  describe "get_config/1" do
    test "provider options take precedence key by key over the shared configuration" do
      Application.put_env(:provider_options_app, Ueberauth.Strategy.Cognito, %{
        auth_domain: "shared.example.com",
        client_id: "shared_client_id",
        client_secret: "shared_client_secret",
        user_pool_id: "shared_user_pool_id",
        aws_region: "us-east-1",
        scope: "openid"
      })

      provider_options = [
        otp_app: :provider_options_app,
        auth_domain: "pool-b.example.com",
        client_id: "pool_b_client_id",
        client_secret: {Function, :identity, ["pool_b_secret"]}
      ]

      conn =
        conn(:get, "/auth/pool_b")
        |> put_private(:ueberauth_request_options, options: provider_options)

      assert %Config{
               # overridden by the provider options, including via MFA
               auth_domain: "pool-b.example.com",
               client_id: "pool_b_client_id",
               client_secret: "pool_b_secret",
               # not set in the provider options, falls back to the shared config
               user_pool_id: "shared_user_pool_id",
               aws_region: "us-east-1",
               scope: "openid"
             } = Config.get_config(conn)

      Application.delete_env(:provider_options_app, Ueberauth.Strategy.Cognito)
    end

    test "provider options alone are sufficient without any shared configuration" do
      provider_options = [
        otp_app: :app_without_shared_config,
        auth_domain: "standalone.example.com",
        client_id: "standalone_client_id",
        client_secret: "standalone_client_secret",
        user_pool_id: "standalone_user_pool_id",
        aws_region: "eu-west-1"
      ]

      conn =
        conn(:get, "/auth/cognito")
        |> put_private(:ueberauth_request_options, options: provider_options)

      assert %Config{
               auth_domain: "standalone.example.com",
               client_id: "standalone_client_id",
               user_pool_id: "standalone_user_pool_id"
             } = Config.get_config(conn)
    end

    test "raises a helpful error when required configuration is missing" do
      Application.put_env(:missing_config_app, Ueberauth.Strategy.Cognito, %{
        client_id: "the_client_id"
      })

      conn =
        conn(:get, "/auth/cognito")
        |> put_private(:ueberauth_request_options, options: [otp_app: :missing_config_app])

      assert_raise ArgumentError, ~r/:auth_domain/, fn ->
        Config.get_config(conn)
      end

      Application.delete_env(:missing_config_app, Ueberauth.Strategy.Cognito)
    end

    test "accepts atom values by converting them to strings" do
      Application.put_env(:atom_config_app, Ueberauth.Strategy.Cognito, %{
        auth_domain: "testdomain.com",
        client_id: "the_client_id",
        client_secret: "the_client_secret",
        user_pool_id: "the_user_pool_id",
        aws_region: "us-east-1",
        uid_field: :sub
      })

      conn =
        conn(:get, "/auth/cognito")
        |> put_private(:ueberauth_request_options, options: [otp_app: :atom_config_app])

      assert %Config{uid_field: "sub"} = Config.get_config(conn)

      Application.delete_env(:atom_config_app, Ueberauth.Strategy.Cognito)
    end

    test "raises a helpful error for unsupported configuration values without leaking them" do
      Application.put_env(:bad_config_app, Ueberauth.Strategy.Cognito, %{
        auth_domain: "testdomain.com",
        client_id: "the_client_id",
        client_secret: 123_456_789,
        user_pool_id: "the_user_pool_id",
        aws_region: "us-east-1"
      })

      conn =
        conn(:get, "/auth/cognito")
        |> put_private(:ueberauth_request_options, options: [otp_app: :bad_config_app])

      exception =
        assert_raise ArgumentError, ~r/unsupported value type .* :client_secret/, fn ->
          Config.get_config(conn)
        end

      # the message must name the key but never include the (possibly secret) value
      refute exception.message =~ "123456789"

      Application.delete_env(:bad_config_app, Ueberauth.Strategy.Cognito)
    end

    test "values returned by MFA tuples are validated and converted like plain values" do
      Application.put_env(:mfa_config_app, Ueberauth.Strategy.Cognito, %{
        auth_domain: "testdomain.com",
        client_id: "the_client_id",
        client_secret: "the_client_secret",
        user_pool_id: "the_user_pool_id",
        aws_region: "us-east-1",
        # atom result is converted to a string, like a plain atom value
        uid_field: {Function, :identity, [:sub]}
      })

      conn =
        conn(:get, "/auth/cognito")
        |> put_private(:ueberauth_request_options, options: [otp_app: :mfa_config_app])

      assert %Config{uid_field: "sub"} = Config.get_config(conn)

      Application.put_env(
        :mfa_config_app,
        Ueberauth.Strategy.Cognito,
        %{
          auth_domain: "testdomain.com",
          client_id: "the_client_id",
          client_secret: {Function, :identity, [123_456_789]},
          user_pool_id: "the_user_pool_id",
          aws_region: "us-east-1"
        }
      )

      exception =
        assert_raise ArgumentError, ~r/unsupported value type .* :client_secret/, fn ->
          Config.get_config(conn)
        end

      refute exception.message =~ "123456789"

      Application.delete_env(:mfa_config_app, Ueberauth.Strategy.Cognito)
    end
  end
end
