# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v0.5.0 (2026-07-17)

This is the first release from [wkirschbaum/ueberauth_cognito](https://github.com/wkirschbaum/ueberauth_cognito), which is now the maintained home of this package (previously mbta/ueberauth_cognito).

- Added per provider configuration, which allows multiple Cognito providers to be set for different user pools.
- Added support for passing `login_hint` and `identity_provider` request params through to the Cognito authorize URL.
- Improved error handling: OAuth error callbacks from Cognito (`error`/`error_description` params) are now surfaced as Ueberauth errors instead of a generic missing-code error.
- Fixed a `Mix.Config` deprecation warning.

## v0.4.0 (2022-03-08)

- BREAKING: remove option to handle refresh tokens by passing as an argument to the callback URL. This approach involved transmitting the refresh token to the browser and as such was in violation of the [OAuth 2.0 RFC](https://datatracker.ietf.org/doc/html/rfc6749#section-10.4).

## v0.3.1 (2022-01-14)

- Add support for configuring scopes to include.

## v0.3.0 (2021-09-01)

- BREAKING: minimum ueberauth version is now 0.7
- Standardize handling of CSRF Attack protection

## v0.2.0 (2020-05-28)

- BREAKING: minimum Elixir version is now 1.7
- Added per app configuration based on the otp_app
- Support some optional parameters for Cognito `/authorize`
- Modified to return `info/1` with the information of User in `Ueberauth.Auth.Info`

Thank you to @mdillavou and @yagince for their contributions to this release!

## v0.1.0 (2019-12-19)

- Initial release
