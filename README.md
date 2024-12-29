# clinvar-checker
The ClinvarChecker is a CLI tool that can cross-check your raw 23andme genetic data against the open-source ClinVar database. This will allow you to see if you have any genetic variants that are associated with diseases or other conditions, since most of this data has been pay-walled by 23andMe.

It is important to note that the ClinVar database is not a diagnostic tool. It's a research tool that aggregates information about genetic variants and their clinical significance - just because a variant matches doesn't necessarily mean that the associated conditions will manifest. This tool is meant to be a starting point for further research and discussion with a healthcare provider.

Additionally, The data in the ClinVar database is constantly being updated, so it's important to keep that in mind when interpreting the results - clinical significance can change over time and be promoted or demoted [1](https://youtu.be/7mnFnoEBOW8). While ClinVar is a comprehensive resource, it does not list of all genetic variants - it's a collection of variants that have been submitted by researchers and clinicians, this field is constantly evolving and **vast** - variants are just one piece of the puzzle when it comes to understanding genetic risk, there are also other factors like family history, lifestyle, and environment that could play a role in determining risk.

**TLDR; This is just a tool to help you understand your genetic data better, it's not a diagnostic tool. Take it with a grain of salt, and don't freak out.**

## Installation & Usage
1. Navigate to the [releases page](https://github.com/ssaunderss/clinvar-checker/releases)
2. Download the latest release for your operating system
3. Make the binary executable `chmod +x clinvar_checker_{$OS}`
4. Optionally move the binary to a directory in your `$PATH` - `mv clinvar_checker_{$OS} /usr/local/bin/clinvar_checker`
5. Now you can run the binary, some example usage:
```bash
> clinvar_checker --help
> clinvar_checker download
> clinvar_checker check path/to/23_and_Me_genome.txt
> clinvar_checker check path/to/23_and_Me_genome.txt --clinical-significance pathogenic
```

## How are single-nucleotide matches determined?
The ClinVar database provides information about genetic variants and their clinical significance with the following relevant pieces of information: `chromosome`, `position`, `reference allele`, and `alternate allele`. The 23andMe data provides information about genetic variants with the following relevant pieces of information: `chromosome`, `position`, and `genotype`. The order of the genotype doesn't matter - `AG` is the same as `GA`. Essentially what we're looking for are matches to the `alternate allele`. Here's a logic table outlining the possible match outcomes for a `reference allele=A` and `alternate allele=G`:

| 23andMe Genotype | Contains Reference Allele (A)? | Contains Alternate Allele (G)? | Match Interpretation | Variant Status |
|-------------------|---------------------------------|---------------------------------|----------------------|----------------|
| AA | Yes (2 copies) | No | Perfect match to reference | No variant present |
| AG | Yes (1 copy) | Yes (1 copy) | Heterozygous match | Heterozygous for variant |
| GA | Yes (1 copy) | Yes (1 copy) | Heterozygous match | Heterozygous for variant |
| GG | No | Yes (2 copies) | Homozygous alt | Homozygous for variant |
| AT | Yes (1 copy) | No | Novel alternate T | No ClinVar variant present |
| TA | Yes (1 copy) | No | Novel alternate T | No ClinVar variant present |
| TT | No | No | Different variant entirely | No ClinVar variant present |
| GT | No | Yes (1 copy) | Mixed variant profile | Heterozygous for variant |
| TG | No | Yes (1 copy) | Mixed variant profile | Heterozygous for variant |
| AC | Yes (1 copy) | No | Novel alternate C | No ClinVar variant present |
| CA | Yes (1 copy) | No | Novel alternate C | No ClinVar variant present |
| CC | No | No | Different variant entirely | No ClinVar variant present |
| GC | No | Yes (1 copy) | Mixed variant profile | Heterozygous for variant |
| CG | No | Yes (1 copy) | Mixed variant profile | Heterozygous for variant |
| TC | No | No | Different variant entirely | No ClinVar variant present |
| CT | No | No | Different variant entirely | No ClinVar variant present |

## Limitations
- This tool only works with raw 23andMe data, it doesn't work with Ancestry or other genetic testing services.
- The format of the 23andMe data does not lend itself to analyzing multi-nucleotide variants (MNVs), e.g. and insertion or deletion of multiple consecutive nucleotides `alt=AG` vs `alt=A` - this tool will not be able to detect these types of variants.

## Development
1. `asdf install` to install all the local dependencies (zig is needed to build the burrito binaries).
2. `brew install p7zip` - only needed if you plan on using burrito to make Windows executables.
3. Unlike traditional Elixir applications, this project doesn't stay running, it only stays alive for the duration of the command. So instead of the typical `iex -S mix` for local development, you'll want to run the commands directly `mix app.start check tmp/23_and_Me_genome.txt --clinical-significance pathogenic`.

## Releases
1. Bump the version in `mix.exs`
2. `MIX_ENV=prod mix release`
3. Binaries are built in `.burrito_out/`
4. `git tag -a v{$VERSION} -m {$MESSAGE} && git push --tags
5. Create a new release on the [releases page](https://github.com/ssaunderss/clinvar-checker/releases)

## TODOs
- [ ] Support different output formats (JSON, CSV, etc.)
