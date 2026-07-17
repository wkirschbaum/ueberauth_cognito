# Ueberauth Cognito

[![Build Status](https://github.com/wkirschbaum/ueberauth_cognito/actions/workflows/elixir.yml/badge.svg?branch=master)](https://github.com/wkirschbaum/ueberauth_cognito/actions/workflows/elixir.yml)

> An Ueberauth Strategy for AWS Cognito.

## Installation

Add `:ueberauth` and `:ueberauth_cognito` to your `mix.exs`:

```elixir
defp deps do
  [
    # ...
    {:ueberauth, "~> 0.7"},
    {:ueberauth_cognito, "~> 0.5"}
  ]
end
```

Configure Ueberauth to use this strategy:

```elixir
config :ueberauth, Ueberauth,
  providers: [
    cognito: {Ueberauth.Strategy.Cognito, []}
  ]
```

and configure the required values:

```elixir
config :ueberauth, Ueberauth.Strategy.Cognito,
  auth_domain: {System, :get_env, ["COGNITO_DOMAIN"]},
  client_id: {System, :get_env, ["COGNITO_CLIENT_ID"]},
  client_secret: {System, :get_env, ["COGNITO_CLIENT_SECRET"]},
  user_pool_id: {System, :get_env, ["COGNITO_USER_POOL_ID"]},
  aws_region: {System, :get_env, ["COGNITO_AWS_REGION"]} # e.g. "us-east-1"
```

The values can be configured with an MFA, or simply a string.

The following optional values can be configured in the same way:

```elixir
config :ueberauth, Ueberauth.Strategy.Cognito,
  # ... required values ...
  scope: "openid profile email", # OAuth scopes to request (this is the default)
  uid_field: "sub",              # id token claim used for `auth.uid` (default: "cognito:username")
  name_field: "name"             # id token claim used for `auth.info.name` (default: "name")
```

Add the routes to the router:

```elixir
scope "/auth", SignsUiWeb do
  pipe_through([:redirect_prod_http, :browser])
  get("/:provider", AuthController, :request)
  get("/:provider/callback", AuthController, :callback)
end
```

and create the corresponding controller:

```elixir
defmodule SignsUiWeb.AuthController do
  use SignsUiWeb, :controller
  plug(Ueberauth)

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    # what to do if sign in fails
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    # sign the user in or something.
    # auth is a `%Ueberauth.Auth{}` struct, with Cognito token info
    send_resp(conn, 200, "Welcome, #{auth.uid}")
  end
end
```

Note that the entry in the `router` defines the authentication callback URL, and will need to be whitelisted in the AWS Cognito User Pools settings.

## Request parameters

The request phase passes the following query parameters through to Cognito's `/oauth2/authorize` endpoint when present, so you can send users to a specific identity provider or pre-fill their username:

```
/auth/cognito?identity_provider=Google
/auth/cognito?idp_identifier=my-idp
/auth/cognito?login_hint=user@example.com
```

## Multiple Cognito providers

To authenticate against more than one user pool (for example separate staff and customer pools), define multiple providers with the Cognito strategy and pass each one its configuration as options:

```elixir
config :ueberauth, Ueberauth,
  providers: [
    staff: {Ueberauth.Strategy.Cognito, [
      auth_domain: "staff.auth.example.com",
      client_id: {System, :get_env, ["STAFF_COGNITO_CLIENT_ID"]},
      client_secret: {System, :get_env, ["STAFF_COGNITO_CLIENT_SECRET"]},
      user_pool_id: "eu-west-1_staff",
      aws_region: "eu-west-1"
    ]},
    customers: {Ueberauth.Strategy.Cognito, [
      auth_domain: "customers.auth.example.com",
      client_id: {System, :get_env, ["CUSTOMER_COGNITO_CLIENT_ID"]},
      client_secret: {System, :get_env, ["CUSTOMER_COGNITO_CLIENT_SECRET"]},
      user_pool_id: "eu-west-1_customers",
      aws_region: "eu-west-1"
    ]}
  ]
```

Each provider gets its own routes (`/auth/staff`, `/auth/customers` above), and `auth.provider` in the callback tells you which one authenticated.

Provider options take precedence key by key: any value not given in a provider's options falls back to the shared `config :ueberauth, Ueberauth.Strategy.Cognito` configuration, so values common to all pools only need to be set once.

## Configuration of settings per OTP app

If you wish to use Ueberauth in multiple OTP apps, and configure each instance of Ueberauth with a different list of Providers and settings, you will need to do some things differently. When providing configuration for Ueberauth, you should set anything that differs by OTP app under the name of your OTP app, for example:

```ex
config :my_app, Ueberauth,
  providers: [
    cognito: {Ueberauth.Strategy.Cognito, []}
  ]
```

and configure the required values for the provider (make sure to use the same otp_app name)

```elixir
config :my_app, Ueberauth.Strategy.Cognito,
  auth_domain: {System, :get_env, ["COGNITO_DOMAIN"]},
  client_id: {System, :get_env, ["COGNITO_CLIENT_ID"]},
  client_secret: {System, :get_env, ["COGNITO_CLIENT_SECRET"]},
  user_pool_id: {System, :get_env, ["COGNITO_USER_POOL_ID"]},
  aws_region: {System, :get_env, ["COGNITO_AWS_REGION"]} # e.g. "us-east-1"
```

In your controller, when using the Ueberauth plug, you should pass the `:otp_app` option, for example:

```elixir
defmodule SignsUiWeb.AuthController do
  use SignsUiWeb, :controller
  plug(Ueberauth, otp_app: :my_app)

  ...
```

## Copyright and License

Copyright (c) 2019 Massachusetts Bay Transportation Authority

Copyright (c) 2021-2026 Wilhelm Kirschbaum

This project was originally developed by the [MBTA](https://github.com/mbta) and is now maintained here.

Source code licensed under [MIT License](./LICENSE.md).
