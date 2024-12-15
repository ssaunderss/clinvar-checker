defmodule ClinvarChecker.Cli do
  @moduledoc """
  CLI interface for ClinVarChecker.

  Handles parsing arguments and executing the appropriate command.
  """
  @spec main([String.t(), ...]) :: any()
  def main(args) do
    ClinvarChecker.MemoryProfiler.profile(fn ->
      args
      |> sanitize_args()
      |> parse_args()
      |> validate_args()
      |> then(fn args ->
        if Mix.env() == :dev do
          IO.inspect(args, label: "Parsed command and args")
        else
          args
        end
      end)
      |> parse_command()
    end)
  end

  def parse_command({["check", input | _cmd], args}) do
    {:ok, _count_matches} = ClinvarChecker.run(input, args)
  end

  def parse_command({["download" | _cmd], _args}) do
    IO.puts("Downloading ClinVar data...\n")

    case ClinvarChecker.download_clinvar_data() do
      {:ok, _} -> IO.puts("ClinVar data downloaded successfully!\n")
      {:error, error} -> IO.puts("Error downloading ClinVar data: #{error}\n")
    end
  end

  def parse_command({["help" | _cmd], _args}) do
    print_help()
  end

  def parse_command({["version" | _cmd], _args}) do
    IO.puts("ClinVar Checker v#{Application.spec(:clinvar_checker, :vsn)}\n")
  end

  def parse_command({cmd, _args}) do
    IO.puts(
      "Error: Unknown command `#{cmd}`. Please use `clinvar-checker help` for intended usage.\n"
    )

    print_help()
    System.halt(1)
  end

  defp parse_args(args) do
    {args, command, _} =
      OptionParser.parse(args,
        strict: [
          help: :boolean,
          output: :string,
          clinical_significance: :string
        ],
        aliases: [
          help: :h,
          output: :o,
          clinical_significance: :cs
        ]
      )

    {command, args}
  end

  defp validate_args({command, args}) do
    case Keyword.get(args, :clinical_significance) do
      nil ->
        {command, args}

      clinical_significance ->
        parsed_cs = clinical_significance |> String.split(",") |> MapSet.new()
        cs_diff = MapSet.difference(parsed_cs, ClinvarChecker.valid_clinical_significances())

        if MapSet.size(cs_diff) > 0 do
          IO.puts(
            "Error: Invalid clinical significance(s) provided: #{inspect(cs_diff |> MapSet.to_list())}"
          )

          System.halt()
        else
          {command, Keyword.put(args, :clinical_significance, parsed_cs)}
        end
    end
  end

  defp sanitize_args(args) do
    Enum.drop_while(args, &(&1 == "start" || &1 == "app.start" || String.ends_with?(&1, "mix")))
  end

  defp print_help() do
    IO.puts("""
      Usage: clinvar-checker analyze /tmp/path_to_23andme_data

      Commands:
        check     Cross-checks ClinVar variants against provided 23andMe data
        download  Downloads the latest ClinVar database
        help      Shows this help message
        version   Shows version information

      Options:
        -h, --help         Shows this help message
        -o, --output       Write ouput to a file instead of stdout
        -cs, --clinical-significance Only shows variants with that match the specified clinical significance, accepts a comma separated list of supported values (pathogenic, likely_pathogenic, uncertain_significance, likely_benign, benign)

      Examples:
        clinvar-checker download
        clinvar-checker check 23andme_data.txt -o clinvar_report.txt -cs pathogenic,likely_pathogenic\n
    """)
  end
end
