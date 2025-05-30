source("packages.R")

(objs <- load("../PeakSeg-paper/dp.peaks.train.RData"))
(objs <- load("dp.peaks.error.RData"))
(objs <- load("dp.peaks.RData"))

library(dplyr)
good.group.df <- groups %>%
  group_by(group) %>%
  summarise(region.values=length(unique(regions))) %>%
  filter(region.values == 1)
good.groups <- good.group.df$group
min.error <- groups %>%
  filter(group %in% good.groups) %>%
  group_by(chunk.name, cell.type, algorithm, regions) %>%
  summarise(min=min(errors)) %>%
  mutate(set.name=sub("/.*", "", chunk.name),
         experiment=sub("_.*", "", set.name))
wide <-
  dcast(min.error,
        chunk.name + cell.type + experiment ~ algorithm,
        value.var="min") %>%
  mutate(baseline=ifelse(experiment=="H3K36me3",
           hmcan.broad.trained, macs.trained),
         advantage=baseline-PeakSeg) %>%
  arrange(advantage)
zero.error <- data.table(wide) %>%
  filter(PeakSeg==0)
biggest <- zero.error %>%
  group_by(experiment) %>%
  mutate(rank=rank(-advantage)) %>%
  filter(rank==1)
biggest$chunk.name[2] <- "H3K36me3_AM_immune/8"
data.frame(biggest)

zero.error %>%
  filter(chunk.name=="H3K36me3_AM_immune/8")

## We will make a plot for the window for which we have the biggest
## advantage, for each mark type.
prefix <- "http://cbio.ensmp.fr/~thocking/chip-seq-chunk-db"
chunks.file <- paste0(prefix, "/chunks.RData")
u <- url(chunks.file)
load(u)
close(u)
rownames(chunks) <- with(chunks, paste0(set.name, "/", chunk.id))

ann.colors <-
  c(noPeaks="#f6f4bf",
    peakStart="#ffafaf",
    peakEnd="#ff4c4c",
    peaks="#a445ee")

region.list <- list()
count.list <- list()
max.list <- list()
peak.list <- list()
error.list <- list()
text.list <- list()
for(experiment.i in 1:nrow(biggest)){
  chunk.info <- biggest[experiment.i, ]
  experiment <- as.character(chunk.info$experiment)
  chunk.name <- as.character(chunk.info$chunk.name)
  more.info <- chunks[chunk.name, ]
  chunkChrom <- as.character(more.info$chunkChrom)
  cell.type <- as.character(chunk.info$cell.type)
  other.algo <-
    ifelse(experiment=="H3K4me3", "macs.trained", "hmcan.broad.trained")
  algorithms <- c("PeakSeg", other.algo)
  param.err <- dp.peaks.train %>%
    inner_join(chunk.info) %>%
    mutate(param.name=as.character(param.num))
  min.params <- param.err %>%
    filter(algorithm %in% algorithms) %>%
    group_by(algorithm) %>%
    filter(seq_along(errors) == which.min(errors))
  default.param.val <-
    ifelse(other.algo=="macs.trained", "1.30103", "2.30258509299405")
  default.param <- param.err %>%
    filter(algorithm==other.algo,
           param.name==default.param.val) %>%
    mutate(algorithm=sub("trained", "default", algorithm))
  show.params <- rbind(default.param, min.params)
  rownames(show.params) <- show.params$algorithm
  ## TODO: download peaks and error regions for baseline, plot them
  ## alongside PeakSeg model.
  dp.error <- dp.peaks.error[[chunk.name]][[cell.type]]
  dp.param <- show.params["PeakSeg", "param.name"]
  dp.regions <- subset(dp.error, param.name==dp.param)
  sample.ids <- as.character(unique(dp.error$sample.id))
  ## Try to show only a subset of samples.
  sample.ids <- sprintf("McGill%04d", c(26))
  dp.peaks.samples <- dp.peaks[[chunk.name]]
  dp.peak.list <- list()
  for(sample.id in sample.ids){
    dp.peak.list[[sample.id]] <-
      data.frame(sample.id, dp.peaks.samples[[sample.id]][[dp.param]]) %>%
        select(sample.id, chromStart, chromEnd)
  }
  ## Download count signal data.
  counts.file <- file.path("data", chunk.name, "counts.RData")
  load(counts.file)
  if(experiment=="H3K36me3"){
    chromStart <- c(111780000, 111795000, 111900000)
    chromEnd <- c(111790000, 111840000, 111960000)
    start <- 111550000
    end <- 111970000
  }else{
    chromStart <- c(175459000)
    chromEnd <- c(175500000)
    start <- 175000000
    end <- 175505000
  }
  dp.regions <- dp.regions %>%
    mutate(chromStart=ifelse(chromStart < start, start, chromStart),
           chromEnd=ifelse(chromEnd < end, chromEnd, end))
  counts <- subset(counts,
                   start < chromStart &
                   chromEnd < end)
  
  sample.counts <- counts %>%
    filter(sample.id %in% sample.ids) %>%
    group_by(sample.id) %>%
    mutate(coverage.norm=coverage/max(coverage))
  tit <-
    sprintf("%s data (%s pattern)",
            experiment, ifelse(experiment=="H3K4me3", "sharp", "broad"))
  sample.max.df <- sample.counts %>%
    group_by(sample.id) %>%
    summarise(count=max(coverage),
              norm=max(coverage.norm))
  sample.max <- sample.max.df$count
  names(sample.max) <- as.character(sample.max.df$sample.id)
  sample.max.df$chromStart <- sample.counts$chromStart[1]
  sample.max.df$chromEnd <- sample.counts$chromEnd[nrow(sample.counts)]

  other.params <- subset(show.params, algorithm != "PeakSeg")
  trained.param <- subset(other.params, grepl("trained", algorithm))
  trained.algo <- as.character(trained.param$algorithm)

  label.sample <- "McGill0026"
  show.peak.list <-
    list(
         bad=data.frame(sample.id=label.sample, chromStart, chromEnd),
      good=do.call(rbind, dp.peak.list))
  label.regions <- subset(dp.regions, sample.id==label.sample)
  label.err <- PeakErrorChrom(show.peak.list$bad, label.regions)
  label.err$sample.id <- label.sample
  show.region.list <-
    list(good=dp.regions,
         bad=label.err)

  compare.region.list <- list()
  compare.peak.list <- list()
  compare.label.list <- list()
  for(algorithm.i in seq_along(show.peak.list)){
    peak.df <- show.peak.list[[algorithm.i]]
    sample.id <- as.character(peak.df$sample.id)[[1]]
    max.count <- sample.max[[sample.id]]
    algorithm <- names(show.peak.list)[[algorithm.i]]
    short.algo <- sub("[.].*", "", algorithm)
    y.mid <- algorithm.i*0.15 + 1.05
    count.mid <- algorithm.i * 3 + 32 
    compare.peak.list[[algorithm]] <-
      data.frame(tit, algorithm, y.mid, count.mid, peak.df)
    ## Also make regions.
    height <- 1
    region.df <- show.region.list[[algorithm]]
    this.param <- show.params[algorithm, ]
    compare.label.list[[algorithm]] <- with(region.df, {
      data.frame(tit, fp=sum(fp), fn=sum(fn),
                 algorithm,
                 y.mid, count.mid,
                 param.name=this.param$param.name)
    })
    sample.id <- as.character(region.df$sample.id)
    max.count <- sample.max[sample.id]
    y.min <- (-algorithm.i*4-height)*max.count/10
    y.max <- (-algorithm.i*4+height)*max.count/10
    compare.region.list[[algorithm]] <-
      data.frame(tit, algorithm, y.mid, count.mid, region.df) %>%
        select(tit, sample.id, y.mid, count.mid, 
               chromStart, chromEnd, annotation, status) %>%
    mutate(chromStart=ifelse(chromStart < start, start, chromStart),
           chromEnd=ifelse(chromEnd < end, chromEnd, end))

  }
  error.list[[experiment.i]] <- do.call(rbind, compare.region.list)
  
  peak.list[[experiment.i]] <- do.call(rbind, compare.peak.list)
  first <- dp.regions %>%
    filter(sample.id==label.sample,
           annotation=="peakStart")
  text.list[[experiment.i]] <- do.call(rbind, compare.label.list) %>%
    mutate(chromStart=first$chromStart[1],
           sample.id=label.sample)

  algo.colors <-
    c(macs.default="#A6CEE3", macs.trained="#1F78B4", #lite dark blue
      hmcan.broad.default="#A6CEE3", hmcan.broad.trained="#1F78B4", #lite dark blue
      bad="#1F78B4", #lite dark blue
      "#B2DF8A", "#33A02C", #green
      "#FB9A99", "#E31A1C", #red
      "#FDBF6F", "#FF7F00", #orange
      "#CAB2D6", PeakSeg="#6A3D9A", #purple
      good="#6A3D9A", #purple
      "#FFFF99", "#B15928") #yellow/brown
  region.list[[experiment.i]] <-
    data.frame(tit, subset(dp.regions, sample.id %in% sample.ids))
  count.list[[experiment.i]] <-
    data.frame(tit, sample.counts)
  max.list[[experiment.i]] <-
    data.frame(tit, sample.max.df)
}#experiment.i

peaks <- do.call(rbind, peak.list)
txt <- do.call(rbind, text.list)
error <- do.call(rbind, error.list)
counts <- do.call(rbind, count.list)
regions <- do.call(rbind, region.list)
maxes <- do.call(rbind, max.list)
scales <-
  data.frame(chromStart=c(175450, 111750),
             y=-2,
             sample.id="McGill0026",
             tit=c("H3K4me3 data (sharp pattern)",
               "H3K36me3 data (broad pattern)")) %>%
  mutate(chromEnd=chromStart+50)
rect.h <- 0.06
selectedPlot <- 
  ggplot()+
  geom_tallrect(aes(xmin=chromStart/1e3, xmax=chromEnd/1e3,
                    fill=annotation),
                data=regions,
                color="grey",
                alpha=1/2)+
  geom_step(aes(chromStart/1e3, coverage.norm),
            data=counts, color="grey50")+
  geom_text(aes(chromStart/1e3, 1, label=sprintf("max=%d", count)),
            vjust=1, hjust=0, data=maxes, size=3)+
  geom_text(aes(chromStart, y, label="scale: 50 kb "),
               data=scales, hjust=1, vjust=0.5, size=3)+
  geom_segment(aes(chromStart, y, xend=chromEnd, yend=y),
               data=scales, size=2)+
  geom_text(aes(chromStart/1e3, y.mid,
                label=paste0(algorithm, " ")),
            data=txt, 
            ##vjust=0.25, size=2,
            size=2.5,
            hjust=1)+
  geom_rect(aes(xmin=chromStart/1e3, xmax=chromEnd/1e3,
                ymin=y.mid -rect.h, ymax=y.mid + rect.h,
                linetype=status),
            data=subset(error, sample.id %in% sample.ids),
            fill=NA, color="black", size=0.5)+
  scale_linetype_manual("error type",
                        values=c(correct=0,
                          "false negative"=3,
                          "false positive"=1))+
  ## geom_point(aes(chromStart/1e3, y.mid, color=algorithm),
  ##            data=peaks,
  ##            pch=1, size=2)+
  geom_segment(aes(chromStart/1e3, y.mid,
                   xend=chromEnd/1e3, yend=y.mid,
                   color=algorithm),
               data=peaks, size=1)+
  scale_color_manual(values=algo.colors)+
  theme_bw()+
  theme(panel.margin=grid::unit(0, "cm"))+
  facet_grid(. ~ tit, scales="free", space="free_y")+
  scale_y_continuous("count of aligned reads",
                     labels=function(x){
                       c("0", "max")
                     },
                     breaks=c(0, 1))+
  guides(color="none")+
  xlab(paste("position on chromosome (kb = kilo bases)"))+
  scale_fill_manual("label", values=ann.colors,
                    breaks=names(ann.colors))

rect.h <- 1
selectedPlot <- 
  ggplot()+
  geom_tallrect(aes(xmin=chromStart/1e3, xmax=chromEnd/1e3,
                    fill=annotation),
                data=regions,
                color="grey",
                alpha=1/2)+
  geom_step(aes(chromStart/1e3, coverage),
            data=counts, color="grey50")+
  geom_text(aes(chromStart, y, label="scale: 50 kb "),
               data=scales, hjust=1, vjust=0.5, size=3)+
  geom_segment(aes(chromStart, y, xend=chromEnd, yend=y),
               data=scales, size=2)+
  geom_text(aes(chromStart/1e3, count.mid,
                label=paste0(algorithm, " ")),
            data=txt, 
            ##vjust=0.25, size=2,
            size=2.5,
            hjust=1)+
  geom_rect(aes(xmin=chromStart/1e3, xmax=chromEnd/1e3,
                ymin=count.mid -rect.h, ymax=count.mid + rect.h,
                linetype=status),
            data=subset(error, sample.id %in% sample.ids),
            fill=NA, color="black", size=0.5)+
  scale_linetype_manual("error type",
                        values=c(correct=0,
                          "false negative"=3,
                          "false positive"=1))+
  geom_segment(aes(chromStart/1e3, count.mid,
                   xend=chromEnd/1e3, yend=count.mid,
                   color=algorithm),
               data=peaks, size=1)+
  scale_color_manual(values=algo.colors)+
  theme_bw()+
  theme(panel.margin=grid::unit(0, "cm"))+
  facet_grid(. ~ tit, scales="free", space="free_y")+
  scale_y_continuous("count of aligned reads", breaks=seq(0, 30, by=10))+
  guides(color="none")+
  xlab(paste("position on chromosome (kb = kilo bases)"))+
  scale_fill_manual("label", values=ann.colors,
                    breaks=names(ann.colors))
print(selectedPlot)

png(png.file <- "figure-good-bad.png",
    units="in", res=200, width=8, height=2.5)
print(selectedPlot)
dev.off()
##system(paste("firefox", png.file))

