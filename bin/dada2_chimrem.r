#!/usr/bin/env Rscript
#########################################
# dada2_chimrem
#
# Run DADA2 chimera removal on DADA2 object given in input.
# Also, produce different output and stats files:
# * Fasta file with representative sequences
# * Counts table
# * Relative counts table
# * Denoising stats for each sample; number of reads before/after
#   denoising and chimera removal
# 
# Author: Jeanette Tångrot (jeanette.tangrot@nbis.se), Daniel Lundin

suppressPackageStartupMessages(library(optparse))

VERSION = 1.0

# Get arguments
option_list = list(
  make_option(
    c('--dadaObj'), type='character', default='dd.rds',
    help='R RDS file with DADA2 object containing denoised reads. Default: "dd.rds"'
  ),
  make_option(
    c('--manifest'), type='character', default='',
    help='Manifest file listing sample names and paths to sequence files. No default.'
  ),
  make_option(
    c('--method'), type='character', default='pooled',
    help='Method for bimera identification. Valid options are "pooled" (all samples are pooled), "consensus" (samples independently checked, consensus decision on each sequence), and "per-sample" (samples are treated independently). Default: "pooled"'
  ),
  make_option(
    c('--allowOneOff'), action="store_true", default=TRUE,
    help='Also flag sequences that have one mismatch or indel to an exact bimera as bimeric. Default: "TRUE"'
  ),
  make_option(
    c('--minab'), type='integer', default=8,
    help='Minimum parent abundance, default %default. See DADA2 R documentation for isBimeraDenovo.'
  ),
  make_option(
    c('--overab'), type='integer', default=2,
    help='Parent overabundance multiplier, default %default. See DADA2 R documentation for isBimeraDenovo.'
  ),
  make_option(
    c('--stats'), type='character', default='denoise_stats.tsv',
    help='File for writing some stats from denoising and chimera removal. Default: "denoise_stats.tsv"'
  ),
  make_option(
    c('--table'), type='character', default='feature-table.tsv',
    help='File for writing counts per sample and ASV. Default: "feature-table.tsv"'
  ),
  make_option(
    c('--reltable'), type='character', default='rel-feature-table.tsv',
    help='File for writing relative abundances of the ASVs. Default: "rel-feature-table.tsv"'
  ),
  make_option(
    c('--repseqs'), type='character', default='sequences.fasta',
    help='File for writing ASV sequences in fasta format. Default: "sequences.fasta"'
  ),
  make_option(
    c("-v", "--threads"), type='integer', default=1,
    help="Number of threads."
  ),
  make_option(
    c('-v', '--verbose'), action="store_true", default=FALSE,
    help="Print progress messages."
  ),
  make_option(
    c('--version'), action="store_true", default=FALSE,
    help="Print version of script and DADA2 library."
  )
)
opt = parse_args(OptionParser(option_list=option_list))

if ( opt$version ) {
  write(sprintf("dada2_chimrem.r version %s, DADA2 version %s", VERSION, packageVersion('dada2')), stderr())
  q('no', 0)
}

# Check options
if ( ! file.exists(opt$dada) ) {
   stop(sprintf("Cannot find %s. See help (-h).\n",opt$dada))
}

# Function for log messages
logmsg = function(msg, llevel='INFO') {
  if ( opt$verbose ) {
    write(
      sprintf("%s: %s: %s", llevel, format(Sys.time(), "%Y-%m-%d %H:%M:%S"), msg),
      stderr()
    )
  }
}

logmsg( sprintf( "Chimera removal with DADA2." ) )

# Load DADA2 library here, to avoid --help and --version taking so long
suppressPackageStartupMessages(library(dada2))
suppressPackageStartupMessages(library(ShortRead))

dd = readRDS(opt$dadaObj)

# Make sequence table
seqtab <- makeSequenceTable(dd)

# Remove chimeras
nochim <- removeBimeraDenovo(
       seqtab,
       method=opt$method,
       allowOneOff=opt$allowOneOff,
       minFoldParentOverAbundance=opt$overab,
       minParentAbundance = opt$minab,
       multithread=opt$threads,
       verbose=opt$verbose
)

# Store stats; track reads through filtering/denoising/chimera removal
getN <- function(x) sum(getUniques(x))
track <- cbind(sapply(dd, getN), rowSums(nochim))
track <- cbind(rownames(track), track)
colnames(track) <- c("file", "denoised", "nonchim")

# Write stats to file opt$stats
write.table( track, file = opt$stats, sep = "\t", row.names = FALSE, quote = FALSE)

logmsg( sprintf( "Creating count tables and generating sequence file." ) )

# Create counts table, write to file opt$table
metadata <- read.table(opt$manifest, header = TRUE, sep = ",", colClasses = "character")
metadata["file"] <- basename(metadata$absolute.filepath)
nochim2 <- base:::as.data.frame(t(nochim))
sample_ids <- metadata$sample.id[match(colnames(nochim2),metadata$file)]
colnames(nochim2) <- sample_ids
nochim2$seq <- row.names(nochim2)
row.names(nochim2) <- paste0("ASV_", seq(nrow(nochim2)))
nochim2 <- cbind(ASV_ID=row.names(nochim2), nochim2)

write("# Generated by script dada2_chimrem.r from dada2 objects", file = opt$table)
suppressWarnings(write.table(nochim2[,1:(length(nochim2)-1)], file = opt$table, sep = "\t", row.names = F, quote = F, col.names = c("#ASV_ID", colnames(nochim2[2:(length(nochim2)-1)])), append=TRUE))

# Write fasta file with ASV sequences to file opt$seqfile
fasta.tab <- nochim2[,c("ASV_ID","seq")]
fasta.tab$ASV_ID <- gsub("ASV_",">ASV_",fasta.tab$ASV_ID)
fasta.tab.join <- c(rbind( fasta.tab$ASV_ID, fasta.tab$seq ))
write( fasta.tab.join, file = opt$repseqs )

# Calculate relative abundances and write to file opt$reltable
nochim2$seq <- NULL
nochim2[,2:length(nochim2)] <- nochim2[,2:length(nochim2)]/colSums(nochim2[,2:length(nochim2)])[col(nochim2[,2:length(nochim2)])]
write("# Generated by script dada2_chimrem.r", file = opt$reltable)
suppressWarnings(write.table(nochim2, file = opt$reltable, sep = "\t", row.names = F, quote = F, col.names = c("#ASV_ID", colnames(nochim2[2:length(nochim2)])), append=TRUE))


logmsg(sprintf("Finished chimera removal"))
