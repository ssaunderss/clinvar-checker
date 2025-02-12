defmodule ClinvarChecker do
  @moduledoc """
  Module for analyzing 23andMe genetic data against ClinVar database entries.
  Handles downloading, parsing, and comparing genetic variants.
  """

  @type args :: [memory_profile: boolean(), clinical_significance: String.t(), output: String.t()]

  @clinvar_download "https://ftp.ncbi.nlm.nih.gov/pub/clinvar/vcf_GRCh37/clinvar.vcf.gz"
  @clinvar_ets_table :clinvar_variants
  @clinvar_file "tmp/clinvar.vcf"
  @clinical_significances MapSet.new([
                            "benign",
                            "likely_benign",
                            "uncertain",
                            "likely_pathogenic",
                            "pathogenic",
                            "uncertain",
                            "drug_response"
                          ])
  @default_output "tmp/variant_analysis_report.txt"

  def valid_clinical_significances(), do: @clinical_significances
  defp stages, do: System.schedulers_online() * 2
  defp microseconds_to_seconds(microseconds), do: microseconds / 1_000_000

  def run(input, args) do
    if File.exists?(@clinvar_file) do
      # Parse both datasets
      {time, personal_variants} = :timer.tc(fn -> parse_23andme_file(input) end)
      IO.puts("23andMe data parsed in #{microseconds_to_seconds(time)} seconds")

      {time, _} = :timer.tc(fn -> parse_clinvar_file(@clinvar_file) end)
      IO.puts("ClinVar data parsed in #{microseconds_to_seconds(time)} seconds")

      # Find matches and generate report
      {time, matches} = :timer.tc(fn -> analyze_variants(personal_variants, args) end)

      IO.puts(
        "Analysis completed in #{microseconds_to_seconds(time)} seconds, found #{Enum.count(matches)} matches"
      )

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

  @spec parse_clinvar_file(file_path :: String.t()) :: ets_table_name :: atom()
  def parse_clinvar_file(path) do
    clinvar_table =
      :ets.new(@clinvar_ets_table, [
        :ordered_set,
        :public,
        :named_table,
        read_concurrency: true,
        write_concurrency: true
      ])

    path
    |> File.stream!([], :line)
    |> Flow.from_enumerable(
      max_demand: 4_000,
      stages: stages(),
      window_trigger: Flow.Window.count(40_000),
      window_period: :infinity
    )
    |> Flow.partition(stages: stages())
    |> Flow.map(&parse_clinvar_line/1)
    |> Flow.map(fn
      nil ->
        nil

      variant ->
        key =
          {variant.chromosome, variant.position, variant.reference, variant.alternate}

        {key, variant}
    end)
    |> Flow.partition(
      key: fn
        {key, _variant} ->
          :erlang.phash2(elem(key, 0), stages())

        val ->
          :erlang.phash2(val, stages())
      end,
      stages: stages()
    )
    |> Flow.map(fn
      {key, variant} -> :ets.insert(clinvar_table, {key, variant})
      _ -> :ok
    end)
    |> Enum.to_list()

    @clinvar_ets_table
  end

  defp parse_clinvar_line("#" <> _rest), do: nil

  defp parse_clinvar_line(line) do
    with [chrom, pos, _id, ref, alt, _qual, _filter, info] <-
           :binary.split(line, "\t", [:global]),
         {position, _} <-
           Integer.parse(pos),
         # We cannot confidently analyze multi-nucleotide variants
         1 <- String.length(ref),
         1 <- String.length(alt) do
      parsed_info = parse_clinvar_info(info)
      normalized_chromosme = normalize_chromosome(chrom)

      %{
        chromosome: normalized_chromosme,
        position: position,
        reference: ref,
        alternate: alt,
        processed_significances: parsed_info.processed_significances,
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

    raw_significance = Map.get(info_map, "CLNSIG", "unknown")

    processed_significances =
      raw_significance
      |> String.split(["|", "/", ","])
      |> Enum.map(&String.downcase/1)
      |> MapSet.new()

    %{
      clinical_significance: raw_significance,
      processed_significances: processed_significances,
      condition: Map.get(info_map, "CLNDN", "unknown")
    }
  end

  @spec parse_23andme_file(file_path :: String.t()) :: %{tuple() => map()}
  def parse_23andme_file(path) do
    if File.exists?(path) do
      path
      |> File.stream!([], :line)
      |> Flow.from_enumerable(
        max_demand: 4_000,
        stages: stages(),
        window_trigger: Flow.Window.count(40_000),
        window_period: :infinity
      )
      |> Flow.partition(stages: System.schedulers_online())
      |> Flow.map(&parse_23andme_line/1)
      |> Flow.map(fn
        nil ->
          nil

        genotype_call ->
          {genotype_call.chromosome, genotype_call.position, genotype_call.genotype,
           genotype_call.rsid}
      end)
      |> Flow.partition(
        key: fn
          {chrom, pos, genotype, _rsid} -> :erlang.phash2({chrom, pos, genotype}, stages())
          val -> :erlang.phash2(val, stages())
        end,
        stages: stages()
      )
      |> Flow.reduce(fn -> [] end, fn
        {_chrom, _pos, _genotype, _rsid} = call, acc -> [call | acc]
        _val, acc -> acc
      end)
      |> Enum.to_list()
    else
      IO.puts("Error: 23andMe data file not found. Please use `clinvar-checker help` for help.\n")
      System.halt(1)
    end
  end

  defp parse_23andme_line("#" <> _), do: nil

  defp parse_23andme_line(line) do
    with [rsid, chromosome, position, genotype] <- :binary.split(line, "\t", [:global]),
         trimmed_genotype <- String.trim(genotype) do
      # Skip "no call" genotypes - 23andMe data not confident enough to call this genotype
      if trimmed_genotype == "--" do
        nil
      else
        %{
          rsid: rsid,
          chromosome: normalize_chromosome(chromosome),
          position: String.to_integer(position),
          genotype: String.trim(genotype)
        }
      end
    else
      _ -> nil
    end
  end

  defp normalize_chromosome("MT"), do: "M"
  defp normalize_chromosome(chrom), do: chrom

  def analyze_variants(personal_data, args) do
    personal_data
    |> Stream.map(fn {chrom, pos, genotype, _rsid} = genotype_call ->
      {genotype_call, matching_variants_for_genotype(chrom, pos, genotype)}
    end)
    |> Stream.reject(fn {_genotype_call, matches} -> is_nil(matches) end)
    |> Stream.map(fn {genotype_call, matches} ->
      {genotype_call,
       Enum.filter(matches, &matches_significance?(&1, args[:clinical_significance]))}
    end)
    |> Enum.flat_map(fn {{chrom, pos, genotype, rsid}, clinvar_entries} ->
      Enum.map(clinvar_entries, fn clinvar_entry ->
        build_report_entry(chrom, pos, genotype, rsid, clinvar_entry)
      end)
    end)
  end

  defp build_report_entry(chrom, pos, genotype, rsid, clinvar_entry) do
    %{
      chromosome: chrom,
      position: pos,
      rsid: rsid,
      genotype: genotype,
      clinical_significance: clinvar_entry.clinical_significance,
      condition: clinvar_entry.condition
    }
  end

  @spec matching_variants_for_genotype(
          chromosome :: String.t(),
          position :: integer(),
          genotype :: String.t()
        ) :: [map()] | nil
  defp matching_variants_for_genotype(chromosome, position, genotype) do
    case String.graphemes(genotype) do
      [a1, a2] ->
        if a1 == a2 do
          homozygous_matches(chromosome, position, a1)
        else
          heterozygous_matches(chromosome, position, a1, a2)
        end

      # this is for males - the X chromosome will only have one allele
      [a1] ->
        homozygous_matches(chromosome, position, a1)
    end
    |> Enum.map(&elem(&1, 1))
    |> then(fn result -> if Enum.empty?(result), do: nil, else: result end)
  end

  # wildcard match alternate alleles when genotype is homozygous
  defp homozygous_matches(chromosome, position, allele) do
    :ets.select(@clinvar_ets_table, [{{{chromosome, position, :_, allele}, :_}, [], [:"$_"]}])
  end

  # since the genotype is heterozygous, we need to check both combinations of alleles for matches
  defp heterozygous_matches(chromosome, position, allele1, allele2) do
    :ets.select(@clinvar_ets_table, [
      {{{chromosome, position, allele1, allele2}, :_}, [], [:"$_"]}
    ]) ++
      :ets.select(@clinvar_ets_table, [
        {{{chromosome, position, allele2, allele1}, :_}, [], [:"$_"]}
      ])
  end

  defp matches_significance?(_clinvar_entry, nil), do: true

  defp matches_significance?(clinvar_entry, clinical_significance) do
    MapSet.intersection(clinvar_entry.processed_significances, clinical_significance)
    |> MapSet.size() > 0
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
