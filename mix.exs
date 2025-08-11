defmodule Sambex.MixProject do
  use Mix.Project

  def project do
    [
      app: :sambex,
      version: "0.1.0-alpha1",
      elixir: "~> 1.18",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      source_url: "https://github.com/wearecococo/sambex",
      homepage_url: "https://wearecococo.com"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:zigler, "~> 0.14", runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
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
end
