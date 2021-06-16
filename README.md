# TB Pipeline #
  
Cleans and QCs reads with fastp and FastQC, classifies with Kraken2 & Mykrobe, removes non-bacterial content, and - by alignment to any minority genomes - disambiguates mixtures of bacterial reads.

Takes as input one directory containing pairs of fastq(.gz) or bam files.
Produces as output one directory per sample, containing the relevant reports & a pair of cleaned fastqs.

## Quick Start ## 
Requires NXF_VER>=20.11.0-edge

The workflow is designed to run with either docker `-profile docker` or singularity `-profile singularity`. Before running the workflow, the images will need to be built by running either `docker/docker_build.sh` or  `singularity/singularity_build.sh` 

E.g. to run the workflow:
```
nextflow run main.nf -profile singularity --filetype fastq --input_dir fq_dir --pattern "*_R{1,2}.fastq.gz" --unmix_myco yes \
--output_dir . --kraken_db /path/to/database --bowtie2_index /path/to/index --bowtie_index_name hg19_1kgmaj

nextflow run main.nf -profile docker --filetype bam --input_dir bam_dir --unmix_myco no \
--output_dir . --kraken_db /path/to/database --bowtie2_index /path/to/index --bowtie_index_name hg19_1kgmaj
```

## Params ##
The following parameters should be set in `nextflow.config` or specified on the command line:

* **input_dir**<br /> 
Directory containing fastq OR bam files
* **filetype**<br />
File type in input_dir. Either "fastq" or "bam"
* **pattern**<br />
Regex to match fastq files in input_dir, e.g. "*_R{1,2}.fq.gz"
* **output_dir**<br />
Output directory
* **unmix_myco**<br />
Do you want to disambiguate mixed-mycobacterial samples by read alignment? Either "yes" or "no"
* **species**<br />
Principal species in each sample, assuming genus Mycobacterium. Default 'null'. If parameter used, takes 1 of 10 values: abscessus, africanum, avium, bovis, chelonae, chimaera, fortuitum, intracellulare, kansasii, tuberculosis
* **kraken_db**<br />
Directory containing `*.k2d` Kraken2 database files (k2_pluspf_16gb_20200919 recommended, obtain from https://benlangmead.github.io/aws-indexes/k2)
* **bowtie2_index**<br />
Directory containing Bowtie2 index (obtain from ftp://ftp.ccb.jhu.edu/pub/data/bowtie2_indexes/hg19_1kgmaj_bt2.zip). The specified path should NOT include the index name
* **bowtie_index_name**<br />
Name of the bowtie index, e.g. hg19_1kgmaj<br />
<br />

For more information on the parameters run `nextflow run main.nf --help`

## Stub-run ##
To test the stub run:
```
nextflow run main.nf -stub -config testing.config
```

## Checkpoints ##
Checkpoints used throughout this workflow to fail a sample/issue warnings:

processes preprocessing:checkFqValidity or preprocessing:checkBamValidity
1. (Fail) If sample does not pass fqtools 'validate' or samtools 'quickcheck', as appropriate.
 
process preprocessing:countReads\
2. (Fail) If sample contains < 100k pairs of raw reads.
 
process preprocessing:fastp\
3. (Fail) If sample contains < 100k pairs of cleaned reads, required to all be > 50bp (cleaning using fastp with --length_required 50 --average_qual 10 --low_complexity_filter --correction --cut_right --cut_tail --cut_tail_window_size 1 --cut_tail_mean_quality 20).

process preprocessing:kraken2\
4. (Fail) If the top family hit is not Mycobacteriaceae\
5. (Fail) If there are fewer than 100k reads classified as Mycobacteriaceae \
6. (Warn) If the top family classification is mycobacterial, but this is not consistent with top genus and species classifications\
7. (Warn) If the top family is Mycobacteriaceae but no G1 (species complex) classifications meet minimum thresholds of > 5000 reads or > 0.5% of the total reads (this is not necessarily a concern as not all mycobacteria have a taxonomic classification at this rank)\
8. (Warn) If sample is mixed or contaminated - defined as containing reads > the 5000/0.5% thresholds from multiple non-human species\
9. (Warn) If sample contains multiple classifications to mycobacterial species complexes, each meeting the > 5000/0.5% thresholds\
10. (Warn) If no species classification meets the 5000/0.5% thresholds\
11. (Warn) If no genus classification meets the 5000/0.5% thresholds
 
process preprocessing:identifyBacterialContaminants\
12. (Fail) If regardless of what Kraken reports, Mykrobe does not make a species-level mycobacterial classification (note that we do not use Kraken mycobacterial classifications other than to determine whether 100k reads are family Mycobacteriaceae; for higher-resolution classification, we defer to Mykrobe)\
13. (Fail) If the sample is not contaminated and the top species hit is not one of the 10 supported Mycobacteria: abscessus|africanum|avium|bovis|chelonae|chimaera|fortuitum|intracellulare|kansasii|tuberculosis\
14. (Fail) If the sample is not contaminated and the top species hit is contrary to the species expected (e.g. "avium" rather than "tuberculosis" - only tested if you provide that expectation)\
15. (Warn) If the top Mykrobe species hit, on the basis of highest % coverage, does not also have the highest median depth\
16. (Warn) If we are unable to associate an NCBI taxon ID to any given contaminant species, which means we will not be able to locate its genome, and thereby remove it as a contaminant\
17. (Warn) If we are unable to determine a URL for the latest RefSeq genome associated with a contaminant species' taxon ID\
18. (Warn) If no complete genome could be found for a contaminant species. The workflow will proceed with alignment-based contaminant removal, but you're warned that there's reduced confidence in detecting reads from this species
 
process preprocessing:downloadContamGenomes\
19. (Fail) If a contaminant is detected but we are unable to download a representative genome, and thereby remove it
 
process preprocessing:summarise\
20. (Fail) If after having taken an alignment-based approach to decontamination, Kraken still detects a contaminant species\
21. (Fail) If after having taken an alignment-based approach to decontamination, the top species hit is not one of the 10 supported Mycobacteria\
22. (Fail) If, after successfully removing contaminants, the top species hit is contrary to the species expected (e.g. "avium" rather than "tuberculosis" - only tested if you provide that expectation)

process clockwork:alignToRef\
23. (Fail) If < 100k reads could be aligned to the reference genome\
24. (Fail) If, after aligning to the reference genome, the average read mapping quality < 10\
25. (Fail) If < 50% of the reference genome was covered at 10-fold depth
