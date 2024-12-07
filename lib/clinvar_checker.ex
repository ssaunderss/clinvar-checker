defmodule ClinvarChecker do
  @moduledoc """
  Module for analyzing 23andMe genetic data against ClinVar database entries.
  Handles downloading, parsing, and comparing genetic variants.
  """

  @type args :: [memory_profile: boolean(), clinical_significance: String.t(), output: String.t()]

  @clinvar_download "https://ftp.ncbi.nlm.nih.gov/pub/clinvar/vcf_GRCh37/clinvar.vcf.gz"
  @clinvar_file "tmp/clinvar.vcf"
  @default_output "tmp/variant_analysis_report.txt"

  def run(input, args) do
    if File.exists?(@clinvar_file) do
      # Parse both datasets
      personal_variants = parse_23andme_file(input)
      clinvar_variants = parse_clinvar_file(@clinvar_file)

      # Find matches and generate report
      matches = analyze_variants(personal_variants, clinvar_variants)

      # Generate report
      generate_report(matches, args[:output])
    else
      IO.puts(
        "Error: ClinVar data not found. Please run `clinvar-checker download` to download the data first.\n"
      )

      System.halt(1)
    end
  end

  @spec download_clinvar_data() ::
          {:ok, file_name :: String.t()} | {:error, error_message :: String.t()}
  def download_clinvar_data() do
    case Req.get!(@clinvar_download, decode_body: false) do
      %Req.Response{status: 200, body: body} ->
        # Save and decompress
        compressed = @clinvar_file <> ".gz"
        File.write!(compressed, body)
        System.cmd("gunzip", ["-f", compressed])

        {:ok, @clinvar_file}

      %Req.Response{status: status} ->
        {:error, "Failed to download ClinVar data. Status: #{status}"}
    end
  end

  @spec parse_clinvar_file(file_path :: String.t()) :: %{tuple() => map()}
  def parse_clinvar_file(path) do
    path
    |> File.stream!([], :line)
    |> Flow.from_enumerable(
      max_demand: 1000,
      stages: System.schedulers_online(),
      window_trigger: Flow.Window.count(10_000),
      window_period: :infinity
    )
    |> Flow.partition(stages: System.schedulers_online())
    |> Flow.reject(&String.starts_with?(&1, "#"))
    |> Flow.map(&parse_clinvar_line/1)
    |> Flow.reject(&is_nil/1)
    |> Flow.map(fn variant ->
      key = {variant.chromosome, variant.position}
      {key, variant}
    end)
    |> Flow.partition(
      key: fn {key, _variant} ->
        :erlang.phash2(elem(key, 0), System.schedulers_online())
      end
    )
    |> Flow.reduce(fn -> %{} end, fn {key, variant}, acc ->
      Map.put(acc, key, variant)
    end)
    |> Flow.take_sort(100_000, fn {key1, _}, {key2, _} ->
      key1 <= key2
    end)
    |> Enum.to_list()
    |> List.flatten()
    |> Enum.into(%{})
  end

  defp parse_clinvar_line(line) do
    with [chrom, pos, _id, ref, alt, _qual, _filter, info] <-
           :binary.split(line, "\t", [:global]),
         {position, _} <- Integer.parse(pos) do
      parsed_info = parse_clinvar_info(info)

      %{
        chromosome: normalize_chromosome(chrom),
        position: position,
        reference: ref,
        alternate: alt,
        clinical_significance: parsed_info.clinical_significance,
        condition: parsed_info.condition
      }
    else
      _ -> nil
    end
  end

  defp parse_clinvar_info(info) when is_binary(info) do
    info_map =
      info
      |> :binary.split(";", [:global])
      |> Enum.reduce(%{}, fn item, acc ->
        case :binary.split(item, "=", [:global]) do
          [key, value] -> Map.put(acc, key, value)
          _ -> acc
        end
      end)

    %{
      clinical_significance: Map.get(info_map, "CLNSIG", "unknown"),
      condition: Map.get(info_map, "CLNDN", "unknown")
    }
  end

  @spec parse_23andme_file(file_path :: String.t()) :: %{tuple() => map()}
  def parse_23andme_file(path) do
    if File.exists?(path) do
      path
      |> File.stream!([], :line)
      |> Flow.from_enumerable(
        max_demand: 1000,
        stages: System.schedulers_online(),
        window_trigger: Flow.Window.count(10_000),
        window_period: :infinity
      )
      |> Flow.partition(stages: System.schedulers_online())
      |> Flow.reject(&String.starts_with?(&1, "#"))
      |> Flow.map(&parse_23andme_line/1)
      |> Flow.reject(&is_nil/1)
      |> Flow.map(fn variant ->
        key = {variant.chromosome, variant.position}
        {key, variant}
      end)
      |> Flow.partition(
        key: fn {key, _variant} ->
          :erlang.phash2(elem(key, 0), System.schedulers_online())
        end
      )
      |> Flow.reduce(fn -> %{} end, fn {key, variant}, acc ->
        Map.put(acc, key, variant)
      end)
      |> Enum.to_list()
      |> List.flatten()
      |> Enum.into(%{})
    else
      IO.puts("Error: 23andMe data file not found. Please use `clinvar-checker help` for help.\n")
      System.halt(1)
    end
  end

  defp parse_23andme_line(line) do
    with [rsid, chromosome, position, genotype] <- :binary.split(line, "\t", [:global]) do
      %{
        rsid: rsid,
        chromosome: normalize_chromosome(chromosome),
        position: String.to_integer(position),
        genotype: String.trim(genotype)
      }
    else
      _ -> nil
    end
  end

  defp normalize_chromosome("MT"), do: "M"
  defp normalize_chromosome(chrom), do: chrom

  def analyze_variants(personal_data, clinvar_data) do
    personal_data
    |> Map.keys()
    |> Enum.reduce([], fn key, matches ->
      case Map.get(clinvar_data, key) do
        nil ->
          matches

        clinvar_entry ->
          personal_variant = Map.get(personal_data, key)

          [
            %{
              chromosome: elem(key, 0),
              position: elem(key, 1),
              rsid: personal_variant.rsid,
              genotype: personal_variant.genotype,
              clinical_significance: clinvar_entry.clinical_significance,
              condition: clinvar_entry.condition
            }
            | matches
          ]
      end
    end)
  end

  defp generate_report(matches, output) do
    report =
      matches
      |> Enum.sort_by(fn match -> {match.chromosome, match.position} end)
      |> Enum.map(fn match ->
        """
        Variant found:
        Chromosome: #{match.chromosome}
        Position: #{match.position}
        rsID: #{match.rsid}
        Your genotype: #{match.genotype}
        Clinical significance: #{match.clinical_significance}
        Associated condition: #{match.condition}
        """
      end)
      |> Enum.join("\n")

    output
    |> validate_output()
    |> File.write!(report)

    {:ok, Enum.count(matches)}
  end

  defp validate_output(nil = _output), do: @default_output

  defp validate_output(output) do
    if String.ends_with?(output, ".txt") do
      output
    else
      IO.puts("Warning: Output file invalid, writing results to #{@default_output}\n")

      @default_output
    end
  end
end
