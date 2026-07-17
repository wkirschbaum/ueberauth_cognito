defmodule Ueberauth.Strategy.Cognito.ConfigTest do
  use ExUnit.Case
  use Plug.Test

  alias Ueberauth.Strategy.Cognito.Config

  describe "get_config/1" do
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

    test "raises a helpful error for unsupported configuration values" do
      Application.put_env(:bad_config_app, Ueberauth.Strategy.Cognito, %{
        auth_domain: "testdomain.com",
        client_id: 12345,
        client_secret: "the_client_secret",
        user_pool_id: "the_user_pool_id",
        aws_region: "us-east-1"
      })

      conn =
        conn(:get, "/auth/cognito")
        |> put_private(:ueberauth_request_options, options: [otp_app: :bad_config_app])

      assert_raise ArgumentError, ~r/unsupported/, fn ->
        Config.get_config(conn)
      end

      Application.delete_env(:bad_config_app, Ueberauth.Strategy.Cognito)
    end
  end
end
