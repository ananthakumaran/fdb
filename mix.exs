defmodule FDB.MixProject do
  use Mix.Project

  @version "6.3.18-0"

  def project do
    [
      app: :fdb,
      make_clean: ["clean"],
      compilers: [:elixir_make] ++ Mix.compilers(),
      version: @version,
      elixir: "~> 1.3",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "FoundationDB client",
      package: package(),
      docs: docs(),
      dialyzer: [
        plt_add_deps: :transitive,
        ignore_warnings: ".dialyzer_ignore",
        flags: [:unmatched_returns, :race_conditions, :error_handling]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:elixir_make, "~> 0.4", runtime: false},
      {:sweet_xml, "~> 0.6", runtime: false},
      {:stream_data, "~> 0.4", only: :test},
      {:timex, "~> 3.3.0", only: :test},
      {:ex_doc, "~> 0.18", only: :dev},
      {:dialyxir, "~> 1.0.0-rc.2", only: [:dev], runtime: false},
      {:benchee, "~> 0.13", only: :dev},
      {:exprof, "~> 0.2.3", only: :dev},
      {:jason, "~> 1.0", only: :dev}
    ]
  end

  defp package do
    %{
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/ananthakumaran/fdb"},
      maintainers: ["ananthakumaran@gmail.com"],
      files: [
        "lib",
        "priv/fdb.options",
        "mix.exs",
        "README*",
        "LICENSE*",
        "Makefile",
        "Makefile.win",
        "c_src"
      ]
    }
  end

  defp docs do
    [
      source_url: "https://github.com/ananthakumaran/fdb",
      source_ref: "v#{@version}",
      main: FDB,
      extras: ["README.md"]
    ]
  end
end
