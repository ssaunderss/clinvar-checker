defmodule ClinvarChecker do
  @moduledoc """
  Module for analyzing 23andMe genetic data against ClinVar database entries.
  Handles downloading, parsing, and comparing genetic variants.
  """

  def run_analysis(personal_data_path) do
    with {:ok, clinvar_path} <- maybe_download_clinvar_data() do
      # Parse both datasets
      personal_variants = parse_23andme_file(personal_data_path)
      clinvar_variants = parse_clinvar_file(clinvar_path)

      # Find matches and generate report
      matches = analyze_variants(personal_variants, clinvar_variants)

      # Generate report
      generate_report(matches)
    end
  end

  @spec maybe_download_clinvar_data() ::
          {:ok, file_name :: String.t()} | {:error, error_message :: String.t()}
  def maybe_download_clinvar_data do
    clinvar_url = "https://ftp.ncbi.nlm.nih.gov/pub/clinvar/vcf_GRCh37/clinvar.vcf.gz"
    output_file = "tmp/clinvar.vcf"

    if File.exists?(output_file) do
      {:ok, output_file}
    else
      case Req.get!(clinvar_url, decode_body: false) do
        %Req.Response{status: 200, body: body} ->
          # Save and decompress
          File.write!("tmp/clinvar.vcf.gz", body)
          System.cmd("gunzip", ["-f", "tmp/clinvar.vcf.gz"])

          {:ok, output_file}

        %Req.Response{status: status} ->
          {:error, "Failed to download ClinVar data. Status: #{status}"}
      end
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

  defp generate_report(matches) do
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

    File.write!("tmp/variant_analysis_report.txt", report)

    {:ok, Enum.count(matches)}
  end
end
