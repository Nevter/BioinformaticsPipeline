#!/usr/bin/env nextflow

params.outDir = "/home/ubuntu/pipelineOutput"
params.readsURL = "ftp://ftp.1000genomes.ebi.ac.uk/vol1/ftp/phase3/data/HG00133/sequence_read/SRR038564_{1,2}.filt.fastq.gz"
params.genomeURL = "ftp://ftp.ncbi.nlm.nih.gov/genomes/all/GCA/000/001/405/GCA_000001405.15_GRCh38/seqs_for_alignment_pipelines.ucsc_ids/GCA_000001405.15_GRCh38_no_alt_analysis_set.fna.gz"

workflow {
  read_urls_ch = channel.fromPath( params.readsURL, checkIfExists: true )
  genome_url_ch = channel.from( params.genomeURL, checkIfExists: true )
  
  retrieveReads(read_urls_ch) | checkFastQFormat | generateReport | uploadToBucket
  retrieveGenome(genome_url_ch) | indexGenome
}

process retrieveReads {
  tag "Retrieve Sequence reads"

  publishDir ${params.outDir}, mode: 'copy', overwrite: false

  input:
  path readsURL

  output:
  path "*.fastq.gz"

  """
  wget ${params.readsURL}
  """
}

process retrieveGenome {
  tag "Retrieve Sequence reads"

  publishDir ${params.outDir}, mode: 'copy', overwrite: false

  input:
  path genomeURL

  output:
  path "GRCh38_no_alt.fa"

  """
  wget ${params.genomeURL} -O GRCh38_no_alt.fa.gz | gunzip
  """
}

process checkFastQFormat {
  tag "FQ Lint check $read"

  input:
  path read

  output: 
  path "$read"
  
  """
  fq lint $read && "$read" || echo "Failed to verify FASTQ files!"
  """
}

process generateReport {
  tag "Generate report for $read"
  
  input:
  path read

  output: 
  path "*.html"

  """
  fastqc -t \$(nproc) ${read}
  """
}

process uploadToBucket {
  tag "Upload to s3 bucket $report"

  input:
  path report 

  """
  aws s3 cp $report s3://ec.sandbox.genomics/reports/
  """
}

process indexGenome {
  tag "Indexing $genome"

  input:
  path genome 

  output: 
  path "$genome" 

  """
  bwa index GRCh38_no_alt.fa
  """
}