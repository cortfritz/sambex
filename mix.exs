defmodule Sambex.MixProject do
  use Mix.Project

  def project do
    [
      app: :sambex,
      version: "0.3.0",
      elixir: "~> 1.18",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      source_url: "https://github.com/wearecococo/sambex",
      homepage_url: "https://wearecococo.com",
      docs: docs(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.github": :test
      ],
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :ssl, :telemetry],
      mod: {Sambex.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:telemetry, "~> 1.0"},
      {:zigler, "~> 0.14", runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "A library for interacting with SMB shares from Elixir"
  end

  defp package do
    [
      name: "sambex",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/wearecococo/sambex"}
    ]
  end

  defp docs do
    [
      main: "getting_started",
      name: "Sambex",
      source_ref: "v#{Application.spec(:sambex, :vsn)}",
      canonical: "http://hexdocs.pm/sambex",
      source_url: "https://github.com/wearecococo/sambex",
      extras: [
        "guides/getting_started.md",
        "guides/hot_folders.md",
        "guides/examples.md",
        "guides/cross_platform_building.md",
        "CHANGELOG.md",
        "README.md"
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.?/,
        "Project Info": ["CHANGELOG.md", "README.md"]
      ],
      groups_for_modules: [
        "Core API": [Sambex],
        "Connection API": [Sambex.Connection, Sambex.ConnectionSupervisor],
        "Hot Folders": [
          Sambex.HotFolder,
          Sambex.HotFolder.Config,
          Sambex.HotFolder.FileFilter,
          Sambex.HotFolder.FileManager,
          Sambex.HotFolder.Handler,
          Sambex.HotFolder.StabilityChecker
        ],
        Internal: [Sambex.Application, Sambex.Nif]
      ],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md", "README.md"]
    ]
  end
end
