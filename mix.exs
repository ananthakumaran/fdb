defmodule FDB.MixProject do
  use Mix.Project

  def project do
    [
      app: :fdb,
      compilers: [:nif] ++ Mix.compilers(),
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      {:ex_doc, "~> 0.18", only: :dev}
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
