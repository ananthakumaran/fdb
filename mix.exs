defmodule FDB.MixProject do
  use Mix.Project

  def project do
    [
      app: :fdb,
      compilers: [:nif] ++ Mix.compilers(),
      version: "0.1.0",
      elixir: "~> 1.3",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [
        plt_add_deps: :transitive,
        flags: [:unmatched_returns, :race_conditions, :error_handling, :underspecs]
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
      {:dialyxir, "~> 0.5", only: [:dev], runtime: false}
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
