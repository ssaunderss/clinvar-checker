defmodule ClinvarChecker.MixProject do
  use Mix.Project

  def project do
    [
      app: :clinvar_checker,
      version: "1.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
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
      {:burrito, "~> 1.0"},
      {:req, "~> 0.5.8"},
      {:flow, "~> 1.2"},
      {:sizeable, "~> 1.0"}
    ]
  end

  defp releases do
    [
      clinvar_checker: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            macos_intel: [os: :darwin, cpu: :x86_64],
            macos_arm: [os: :darwin, cpu: :aarch64],
            linux: [os: :linux, cpu: :x86_64],
            windows: [os: :windows, cpu: :x86_64]
          ]
        ]
      ]
    ]
  end
end
