defmodule FDB.MixProject do
  use Mix.Project

  @version "5.1.7-1"

  def project do
    [
      app: :fdb,
      compilers: [:nif] ++ Mix.compilers(),
      version: @version,
      elixir: "~> 1.3",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "FoundationDB client",
      package: package(),
      docs: docs(),
      dialyzer: [
        plt_add_deps: :transitive,
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
      {:sweet_xml, "~> 0.6"},
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
      files: ["lib", "priv/fdb.options", "mix.exs", "README*", "LICENSE*", "Makefile"]
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

defmodule Mix.Tasks.Compile.Nif do
  def run(_args) do
    File.mkdir("priv")

    {result, error_code} = System.cmd("make", [], stderr_to_stdout: true)
    IO.binwrite(result)

    if error_code != 0 do
      raise Mix.Error,
        message: """
        Could not run `make`.
        Please check if `make` and either `clang` or `gcc` are installed
        """
    end

    Mix.Project.build_structure()
    :ok
  end
end
