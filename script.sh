#!/usr/bin/env bash

# Setup
## Update apt cache
sudo apt-get update

## Install miniconda
mkdir -p ~/miniconda3
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda3/miniconda.sh
bash ~/miniconda3/miniconda.sh -b -u -p ~/miniconda3
rm -rf ~/miniconda3/miniconda.sh
~/miniconda3/bin/conda init bash
source ~/.profile

## Setup miniconda
conda config --add channels defaults
conda config --add channels bioconda
conda config --add channels conda-forge
conda config --set channel_priority strict

conda create -n bioinfo -c bioconda fq==0.11.0 bwa==0.7.17 fastqc==0.11.8 samtools==1.9 bcftools==1.9 -y

## Install and configure AWS CLI
sudo apt-get install unzip
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm awscliv2.zip
rm -r aws

export AWS_ACCESS_KEY_ID="your_access_key_id"
export AWS_SECRET_ACCESS_KEY="your_secret_access_key"
export AWS_DEFAULT_REGION="your_region"

# Install Java
sudo apt install openjdk-17-jdk
sudo apt install openjdk-17-jre

mkdir picard
cd picard
wget https://github.com/broadinstitute/picard/releases/download/3.1.1/picard.jar

cd ~

# Enter Conda Environment
conda activate bioinfo

# Sequence Read
## Retrieve
mkdir thousand_genomes
cd thousand_genomes
wget ftp://ftp.1000genomes.ebi.ac.uk/vol1/ftp/phase3/data/HG00133/sequence_read/SRR038564_{1,2}.filt.fastq.gz

## Ensure the reads are linted correctly
fq lint SRR038564_1.filt.fastq.gz SRR038564_2.filt.fastq.gz && echo "Successfully verified FASTQ files." || { echo "Failed to verify FASTQ files!"; exit 1; }

## Generate reports
fastqc -t `nproc` SRR038564_1.filt.fastq.gz SRR038564_2.filt.fastq.gz

## Upload reports to S3
aws s3 cp SRR038564_1.filt_fastqc.hmtl s3://ec.sandbox.genomics/reports/
aws s3 cp SRR038564_2.filt_fastqc.html s3://ec.sandbox.genomics/reports/

cd ~

# Reference Genome
## Retrieve
mkdir reference_genome
cd reference_genome
wget ftp://ftp.ncbi.nlm.nih.gov/genomes/all/GCA/000/001/405/GCA_000001405.15_GRCh38/seqs_for_alignment_pipelines.ucsc_ids/GCA_000001405.15_GRCh38_no_alt_analysis_set.fna.gz -O GRCh38_no_alt.fa.gz
gunzip GRCh38_no_alt.fa.gz

## Index
bwa index GRCh38_no_alt.fa GRCh38_no_alt

cd ~
# Align and get varients
mkdir aligned
bwa mem -t `nproc` ./reference_genome/GRCh38_no_alt.fa ./thousand_genomes/SRR038564_1.filt.fastq.gz ./thousand_genomes/SRR038564_2.filt.fastq.gz > ./aligned/SRR038564.bwa-mem.sam
samtools sort ./aligned/SRR038564.bwa-mem.sam > ./aligned/SRR038564.bwa-mem.sorted.bam

## Mark duplicates
java -jar ./picard/picard.jar MarkDuplicates I=./aligned/SRR038564.bwa-mem.sorted.bam O=./aligned/SRR038564.bwa-mem.sorted.marked.bam M=./aligned/SRR038564.bwa-mem.sorted.marked.bam.metrics

## Index bam file
samtools flagstat ./aligned/SRR038564.bwa-mem.sorted.marked.bam
samtools index ./aligned/SRR038564.bwa-mem.sorted.marked.bam

## Get varients
bcftools mpileup -Ou ./aligned/SRR038564.bwa-mem.sorted.marked.bam -f ./reference_genome/GRCh38_no_alt.fa --threads `nproc` | bcftools call -mv > ./SRR038564.called.vcf
grep -v "^#" ./SRR038564.called.vcf | wc -l
bcftools view -i '%QUAL>=20' ./SRR038564.called.vcf | wc -l