defmodule UeberauthCognito.MixProject do
  use Mix.Project

  @source_url "https://github.com/wkirschbaum/ueberauth_cognito"
  @version "0.6.0"

  def project do
    [
      app: :ueberauth_cognito,
      name: "Ueberauth Cognito",
      source_url: @source_url,
      version: @version,
      # hackney 4.x requires OTP 27+, and Elixir 1.17 is the first release
      # that supports OTP 27.
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      test_coverage: [tool: LcovEx],
      description: "An Ueberauth strategy for integrating with AWS Cognito",
      package: package(),
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:lcov_ex, "~> 0.2", only: [:dev, :test], runtime: false},
      {:hackney, "~> 4.0"},
      {:jason, "~> 1.0"},
      {:jose, "~> 1.0"},
      {:ueberauth, "~> 0.7"},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      maintainers: [
        "Wilhelm Kirschbaum <wkirschbaum@gmail.com>"
      ],
      links: %{
        "Changelog" => "https://hexdocs.pm/ueberauth_cognito/changelog.html",
        "GitHub" => @source_url
      }
    ]
  end

  defp docs do
    [
      extras: [
        "CHANGELOG.md": [],
        "LICENSE.md": [title: "License"],
        "README.md": [title: "Overview"]
      ],
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      formatters: ["html"]
    ]
  end
end
