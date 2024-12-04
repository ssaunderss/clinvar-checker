defmodule ClinvarChecker.MixProject do
  use Mix.Project

  def project do
    [
      app: :clinvar_checker,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ClinvarChecker.Application, []}
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5.8"},
      {:flow, "~> 1.2"},
      {:sizeable, "~> 1.0", only: :dev}
    ]
  end
end
