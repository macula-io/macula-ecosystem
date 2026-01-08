defmodule MaculaEcosystem.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/macula-io/macula-ecosystem"

  def project do
    [
      app: :macula_ecosystem,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      name: "Macula Ecosystem",
      description: "Documentation and guides for the Macula distributed application platform",
      source_url: @source_url,
      homepage_url: "https://macula.io"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "overview",
      logo: "assets/logo.svg",
      extras: [
        "guides/overview.md",
        "guides/architecture.md",
        "guides/getting-started.md",
        "guides/event-sourcing.md",
        "guides/mesh-networking.md",
        "guides/neuroevolution.md",
        "guides/macula-os.md",
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ],
      assets: %{
        "assets" => "assets"
      },
      source_ref: "v#{@version}",
      source_url: @source_url,
      formatters: ["html"]
    ]
  end

  defp package do
    [
      name: "macula_ecosystem",
      files: ~w(lib guides assets .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Macula" => "https://github.com/macula-io/macula",
        "ReckonDB" => "https://github.com/reckon-db-org/reckon-db",
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      maintainers: ["Macula Team"]
    ]
  end
end
