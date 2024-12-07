# clinvar-checker
This tool is still actively WIP. The goal is to provide a CLI tool that can cross-check your raw 23andme genetic data against the open-source ClinVar database. This will allow you to see if you have any genetic variants that are associated with diseases or other conditions, since most of this data has been paywalled by 23andMe.

Simple CLI tool to cross-check your raw 23andMe genetic data against the ClinVar database

## TODOs
- [x] Build the CLI tool
  - [x] Download the ClinVar database
  - [x] Cross-check user input 23andme data against the ClinVar database
  - [ ] Optional flag for clinical significance
- [ ] Make releases
- [ ] Build out README - how to use, install, technical stuff, the algorithm for cross-checking
- [ ] Research alternate alleles
- [ ] Better aggregations based on likelihood of disease
