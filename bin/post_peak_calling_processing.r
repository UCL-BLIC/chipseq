#!/usr/bin/env Rscript

# R scripts for processing MACS output files (.xls)
# Author @chuan-wang https://github.com/chuan-wang

# Command line arguments
args <- commandArgs(trailingOnly = TRUE)

R_lib <- as.character(args[1])
ref <- as.character(args[2])
Blacklist <- as.character(args[3])
GTF <- as.character(args[4])
input <- as.character(args[5:length(args)])



# Load / install required packages
.libPaths(c(R_lib, .libPaths()))

if (!require("GenomicRanges")) {
    source("http://bioconductor.org/biocLite.R")
    biocLite("GenomicRanges", suppressUpdates = TRUE)
    library("GenomicRanges")
}

if (!require("ChIPpeakAnno")) {
    source("http://bioconductor.org/biocLite.R")
    biocLite("ChIPpeakAnno", suppressUpdates = TRUE)
    library("ChIPpeakAnno")
}

if (!require("rtracklayer")) {
    source("http://bioconductor.org/biocLite.R")
    biocLite("rtracklayer", suppressUpdates = TRUE)
    library("rtracklayer")
}

if (!require("doParallel")) {
    source("http://bioconductor.org/biocLite.R")
    biocLite("doParallel", suppressUpdates = TRUE)
    library("doParallel")
}
if (!require("parallel")) {
    source("http://bioconductor.org/biocLite.R")
    biocLite("parallel", suppressUpdates = TRUE)
    library("parallel")
}

# Process annotation file
gtf <- import(GTF)

cores <- detectCores() / 2
registerDoParallel(cores)

annotation <- as.data.frame(gtf)

###################################################################
###################################################################
## LC EDITS
###################################################################
annotation <- annotation[annotation$type == 'CDS',]
###################################################################
###################################################################

annotation <- annotation[!duplicated(annotation), ]
annotation <- makeGRangesFromDataFrame(annotation, keep.extra.columns = T)

###################################################################
###################################################################
## LC EDITS
#- some gene_ids are NA, so add na.omit
#- not all the gft's have gene_name, so correct that
#- replace '== x' with '%in% x' or it crashes
#- remove the "gap" correction, as it was making a mess for genes mapped in different chrs
#	> df
#	  seqnames     start       end width strand   symbol  gene_id
#	1     chr2  36389911  36389995    85      + Mir684-1 Mir684-1
#	2     chr2  80628705  80628790    86      - Mir684-1 Mir684-1
#	3     chr5  24257528  24257612    85      + Mir684-1 Mir684-1
#	4     chr7 127398916 127399000    85      + Mir684-1 Mir684-1
#	5    chr10 129665755 129665839    85      + Mir684-1 Mir684-1
#	6    chr11  75065907  75065991    85      - Mir684-1 Mir684-1
#	7    chr11 115523132 115523216    85      - Mir684-1 Mir684-1
#	8    chr16  20176150  20176234    85      - Mir684-1 Mir684-1
#	9     chrX   7753089   7753173    85      + Mir684-1 Mir684-1
#	> df$start <- min(df$start, na.rm=T)
#	> df$end <- max(df$end, na.rm=T)
#	> df
#	  seqnames   start       end width strand   symbol  gene_id
#	1     chr2 7753089 129665839    85      + Mir684-1 Mir684-1
#	2     chr2 7753089 129665839    86      - Mir684-1 Mir684-1
#	3     chr5 7753089 129665839    85      + Mir684-1 Mir684-1
#	4     chr7 7753089 129665839    85      + Mir684-1 Mir684-1
#	5    chr10 7753089 129665839    85      + Mir684-1 Mir684-1
#	6    chr11 7753089 129665839    85      - Mir684-1 Mir684-1
#	7    chr11 7753089 129665839    85      - Mir684-1 Mir684-1
#	8    chr16 7753089 129665839    85      - Mir684-1 Mir684-1
#	9     chrX 7753089 129665839    85      + Mir684-1 Mir684-1
###################################################################
#anno <- plyr::adply(unique(annotation$gene_id),
#                    .margins = 1,
#                    function(x) {
#                        aux <- reduce(annotation[annotation$gene_id == x])
#                        aux$symbol <- unique(annotation[annotation$gene_id == x]$gene_name)
#                        aux$gene_id <- x
#                        df <- as.data.frame(aux)
#                        # For some ENSG genes, there is a small gap between transcripts
#                        df$start <- min(df$start)
#                        df$end <- max(df$end)
#                        df
#                    }, .id = NULL, .parallel = TRUE)
anno <- plyr::adply(unique(na.omit(annotation$gene_id)),
                    .margins = 1,
                    function(x) {
			aux <- reduce(annotation[annotation$gene_id %in% x])
			if(is.null(annotation$gene_name)){
                        	aux$symbol <- unique(annotation[annotation$gene_id %in% x]$gene_id)
			}else{
                        	aux$symbol <- unique(annotation[annotation$gene_id %in% x]$gene_name)
			}
                        aux$gene_id <- x
                        df <- as.data.frame(aux)
                        df
                    }, .id = NULL, .parallel = TRUE)
###################################################################
###################################################################


annoData <- unique(makeGRangesFromDataFrame(anno, keep.extra.columns = T))
names(annoData) <- annoData$gene_id


###################################################################
###################################################################
## LC EDITS
#- keep the 'chr'
###################################################################
## Read in blacklist file and convert into range object
#if (Blacklist != "No-filtering") {
#    blacklist <- read.table(Blacklist, header = FALSE)
#    blacklist_range <- with(blacklist, 
#                            GRanges(sub("chr", "", V1), 
#                                    IRanges(start = V2, end = V3), 
#                                    strand = Rle(rep("+", nrow(blacklist)))
#                                    )
#                            )
#}
if (Blacklist != "No-filtering") {
    blacklist <- read.table(Blacklist, header = FALSE)
    blacklist_range <- with(blacklist, 
                            GRanges(V1, 
                                    IRanges(start = V2, end = V3), 
                                    strand = Rle(rep("+", nrow(blacklist)))
                                    )
                            )
}
###################################################################
###################################################################

# Process output files from MACS: filtering peaks that overlap with blacklisted regions and annotating peaks
for (i in 1:length(input)) {
    # Avoid error that result file with 0 peak identified
    if (class(try(read.table(input[i], header = TRUE), silent = TRUE))  ==  "try-error") next
    # Read in raw peaks from MACS and convert into range object
    data <- read.table(input[i], header = TRUE)
    data_range <- with(data,
                       GRanges(
                               chr,
                               IRanges(start = start, end = end),
                               strand = Rle(rep("+", nrow(data))),
                               length = length,
                               pileup = pileup,
                               pvalue = X.log10.pvalue.,
                               fold_enrichment = fold_enrichment,
                               qvalue = X.log10.qvalue.,
                               id = name
                               )
                       )

    # Filtering peaks that overlap with blacklisted regions
    if (Blacklist != "No-filtering") {
        final <- data_range[data_range %outside% blacklist_range]
        filter_flag <- "_filtered"
    } else{
        final <- data_range
        filter_flag <- ""
    }

    # Write peaks to txt and bed files
    final_df <- as.data.frame(final)
    newfilename <- paste(sub("_peaks.xls", "", basename(input[i])), filter_flag, ".txt", sep = "")

    write.table(final_df, file = newfilename, quote = FALSE, sep = "\t", eol = "\n")

    df <- data.frame(seqnames = seqnames(final),
                     starts = start(final) - 1,
                     ends = end(final),
                     names = c(rep(".", length(final))),
                     scores = c(rep(".", length(final))),
                     strands = strand(final)
                     )
    newfilename <- paste(sub("_peaks.xls", "", basename(input[i])), filter_flag, ".bed", sep = "")

    write.table(df, file = newfilename, quote = F, sep = "\t", row.names = F, col.names = F)


   # Annotation
    final_anno <- annotatePeakInBatch(
                                      final,
                                      AnnotationData = annoData,
                                      output = "overlapping",
                                      maxgap = 5000L
                                      )
 
###################################################################
###################################################################
## LC EDITS
#- add rownmaes = null or it fails when the rownmaes (gene_ids) are
#-	not unique (happens with multiple CDSs for the same gene int he gft
###################################################################
#    # Write annotated peaks to file
#    final_anno_df <- as.data.frame(final_anno)
   final_anno_df <- as.data.frame(final_anno, row.names=NULL)
###################################################################
###################################################################
    final_anno_df$gene_symbol <- anno[match(final_anno_df$feature, anno$gene), ]$symbol

    newfilename <- paste(sub("_peaks.xls", "", basename(input[i])), filter_flag, "_annotated.txt", sep = "")

    write.table(final_anno_df, file = newfilename, quote = FALSE, sep = "\t", eol = "\n")
}


# Show software versions
sessionInfo()
