source("packages.R")

data(chr11ChIPseq)

sample.id <- "McGill0322"
coverage.list <- split(chr11ChIPseq$coverage, chr11ChIPseq$coverage$sample.id)
compressed <- coverage.list[[sample.id]]
compressed$bases <- with(compressed, chromEnd-chromStart)
count <- with(compressed, rep(count, bases))
base <- with(compressed, (chromStart[1]+1):chromEnd[length(chromEnd)])
counts <- data.frame(base, count)

max.segments <- 7
maxPeaks <- as.integer((max.segments-1)/2)
fit <- Segmentor(count, Kmax=max.segments)
Segmentor.segs <- NULL
Segmentor.breaks <- NULL
for(model.i in seq(1, max.segments, by=2)){
  peaks <- (model.i-1)/2
  last.i <- fit@breaks[model.i, 1:model.i]
  break.after <- last.i[-model.i]
  first.i <- c(1, break.after+1)
  param <- fit@parameters[model.i, 1:model.i]
  for(segment.i in seq_along(first.i)){
    from <- first.i[[segment.i]]
    to <- last.i[[segment.i]]
    seg.mean <- param[[segment.i]]
    y <- count[from:to]
  }
  signs <- as.integer(sign(diff(param)))
  feasible <- all(cumsum(signs) %in% c(0,1))
  meta <-
    data.frame(peaks,
               feasible,
               segments=model.i)
  if(length(break.after)){
    Segmentor.breaks <- rbind(Segmentor.breaks, {
      data.frame(meta, chromEnd=base[break.after])
    })
  }
  Segmentor.segs <- rbind(Segmentor.segs, {
    data.frame(meta,
               chromStart=base[first.i],
               chromEnd=base[last.i],
               mean=param,
               row.names=NULL)
  })
}

dp.fit <- PeakSegDP(compressed, maxPeaks=maxPeaks)

cfac <- function(x)factor(x, c("unconstrained", "constrained"))
seg.cols <- c("segments", "chromStart", "chromEnd", "mean")
both.segs <-
  rbind(data.frame(Segmentor.segs[,seg.cols], model=cfac("unconstrained")),
        data.frame(dp.fit$segments[,seg.cols], model=cfac("constrained")))
break.cols <- c("segments", "chromEnd")
both.breaks <-
  rbind(data.frame(Segmentor.breaks[,break.cols], model=cfac("unconstrained")),
        data.frame(dp.fit$breaks[,break.cols], model=cfac("constrained")))

ann.colors <-
  c(noPeaks="#f6f4bf",
    peakStart="#ffafaf",
    peakEnd="#ff4c4c",
    peaks="#a445ee")

## Confront the PeakSegDP model with the annotated regions.
region.list <- split(chr11ChIPseq$regions, chr11ChIPseq$regions$sample.id)
regions <- region.list[[sample.id]]
error.list <- list()
for(peaks in names(dp.fit$peaks)){
  peak.df <- dp.fit$peaks[[peaks]]
  segments <- as.integer(peaks)*2 + 1
  error.list[[peaks]] <-
    data.frame(PeakErrorChrom(peak.df, regions),
               peaks, segments, model=cfac("constrained"))
}
error.regions <- do.call(rbind, error.list)

segs.regions <-
  ggplot()+
  scale_fill_manual("label", values=ann.colors, 
                    breaks=names(ann.colors))+
  scale_linetype_manual("error type", 
                        values=c(correct=0,
                          "false negative"=3,
                          "false positive"=1))+
  scale_y_continuous(breaks=seq(0, 50, by=25), minor_breaks=NULL)+
  scale_x_continuous("position on chr11 (kilo bases)",
                     breaks=seq(118080, 118120, by=20))+
  theme_bw()+
  theme(panel.margin=grid::unit(0, "cm"))+
  facet_grid(segments ~ model, scales="free")+
  geom_step(aes(chromStart/1e3, count),
            data=compressed, color="grey40")+
  geom_segment(aes((chromStart-1/2)/1e3, mean,
                   xend=(chromEnd+1/2)/1e3, yend=mean),
               data=both.segs, color="green", alpha=3/4, size=1)+
  geom_vline(aes(xintercept=(chromEnd+1/2)/1e3),
             data=both.breaks,
             color="green")+
  ylab("count of aligned reads")

png("figure-Segmentor-PeakSeg-noregions.png",
    units="in", res=200, width=6, height=3)
print(segs.regions)
dev.off()

for(suffix in c("constrained", "unconstrained")){
segs.regions <-
  ggplot()+
  scale_fill_manual("label", values=ann.colors, 
                    breaks=names(ann.colors))+
  scale_linetype_manual("error type", 
                        values=c(correct=0,
                          "false negative"=3,
                          "false positive"=1))+
  scale_y_continuous(breaks=seq(0, 50, by=25), minor_breaks=NULL)+
  scale_x_continuous("position on chr11 (kilo bases)",
                     breaks=seq(118080, 118120, by=20))+
  theme_bw()+
  theme(panel.margin=grid::unit(0, "cm"))+
  facet_grid(segments ~ model, scales="free")+
  geom_step(aes(chromStart/1e3, count),
            data=compressed, color="grey40")+
  geom_segment(aes((chromStart-1/2)/1e3, mean,
                   xend=(chromEnd+1/2)/1e3, yend=mean),
               data=subset(both.segs, model==suffix),
               color="green", alpha=3/4, size=1)+
  geom_vline(aes(xintercept=(chromEnd+1/2)/1e3),
             data=subset(both.breaks, model==suffix),
             color="green")+
  ylab("count of aligned reads")

png(sprintf("figure-Segmentor-PeakSeg-%s.png", suffix),
    units="in", res=200, width=6, height=3)
print(segs.regions)
dev.off()
}

segs.regions <-
  ggplot()+
  geom_tallrect(aes(xmin=chromStart/1e3, xmax=chromEnd/1e3,
                    fill=annotation),
                data=error.regions, alpha=1/2)+
  scale_fill_manual("label", values=ann.colors, 
                    breaks=names(ann.colors))+
  scale_linetype_manual("error type", 
                        values=c(correct=0,
                          "false negative"=3,
                          "false positive"=1))+
  scale_y_continuous(breaks=seq(0, 50, by=25), minor_breaks=NULL)+
  scale_x_continuous("position on chr11 (kilo bases)",
                     breaks=seq(118080, 118120, by=20))+
  theme_bw()+
  theme(panel.margin=grid::unit(0, "cm"))+
  facet_grid(segments ~ model, scales="free")+
  geom_step(aes(chromStart/1e3, count),
            data=compressed, color="grey40")+
  geom_segment(aes((chromStart-1/2)/1e3, mean,
                   xend=(chromEnd+1/2)/1e3, yend=mean),
               data=subset(both.segs, model=="constrained"),
               color="green", alpha=3/4, size=1)+
  geom_vline(aes(xintercept=(chromEnd+1/2)/1e3),
             data=subset(both.breaks, model=="constrained"),
             color="green")+
  geom_tallrect(aes(xmin=chromStart/1e3, xmax=chromEnd/1e3),
                data=error.regions,
                fill=NA, color="grey")+
  ylab("count of aligned reads")+
  geom_tallrect(aes(xmin=chromStart/1e3, xmax=chromEnd/1e3,
                    linetype=status),
                data=error.regions,
                fill=NA, color="black", size=1)

png("figure-Segmentor-PeakSeg-constrained-regions.png",
    units="in", res=200, width=6, height=3)
print(segs.regions)
dev.off()

segs.regions <-
  ggplot()+
  ## geom_tallrect(aes(xmin=chromStart/1e3, xmax=chromEnd/1e3,
  ##                   fill=annotation),
  ##               data=error.regions, alpha=1/2)+
  scale_fill_manual("label", values=ann.colors, 
                    breaks=names(ann.colors))+
  scale_linetype_manual("error type", 
                        values=c(correct=0,
                          "false negative"=3,
                          "false positive"=1))+
  scale_y_continuous(breaks=seq(0, 50, by=25), minor_breaks=NULL)+
  scale_x_continuous("position on chr11 (kilo bases)",
                     breaks=seq(118080, 118120, by=20))+
  theme_bw()+
  theme(panel.margin=grid::unit(0, "cm"))+
  facet_grid(segments ~ model, scales="free", labeller=function(df){
    ##browser()
    if("segments" %in% names(df)){
      df$segments <- paste("s =", df$segments)
    }
    if("model" %in% names(df)){
      df$model <- paste(df$model)
    }
    df
  })+
  geom_step(aes(chromStart/1e3, count),
            data=compressed, color="grey40")+
  geom_segment(aes((chromStart-1/2)/1e3, mean,
                   xend=(chromEnd+1/2)/1e3, yend=mean),
               data=both.segs, color="green", alpha=3/4, size=1)+
  geom_vline(aes(xintercept=(chromEnd+1/2)/1e3),
             data=both.breaks,
             linetype="dashed",
             color="green")+
  ## geom_text(aes(118105, 60, label=sprintf("log Lik = %.1f", log.lik)),
  ##           data=lik)+
  ## geom_tallrect(aes(xmin=chromStart/1e3, xmax=chromEnd/1e3),
  ##               data=error.regions,
  ##               fill=NA, color="grey")+
  ylab("count of aligned reads")
  ## geom_tallrect(aes(xmin=chromStart/1e3, xmax=chromEnd/1e3,
  ##                   linetype=status),
  ##               data=error.regions,
  ##               fill=NA, color="black", size=1)

png("figure-Segmentor-PeakSeg.png",
    units="in", res=200, width=9, height=3)
print(segs.regions)
dev.off()
