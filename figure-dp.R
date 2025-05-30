source("packages.R")

chunk.name <- "H3K36me3_AM_immune/8"
chunk.name <- "H3K4me3_PGP_immune/7"

counts.file <- file.path("data", chunk.name, "counts.RData")
load(counts.file)

counts.list <- split(counts, counts$sample.id)
sample.id <- "McGill0026"
sample.counts <- counts.list[[sample.id]]
cell.type <- as.character(sample.counts$cell.type[1])

sample.counts$weight <- with(sample.counts, chromEnd-chromStart)
n <- nrow(sample.counts)
l <- 400
seg2.starts <- as.integer(seq(1, n, l=l)[-c(1, l)])
loss.list <- list()
mean.mat <- matrix(NA, length(seg2.starts), 2)
for(model.i in seq_along(seg2.starts)){
  seg2.start <- seg2.starts[[model.i]]
  seg2.chromStart <- sample.counts$chromStart[seg2.start]
  seg.starts <- c(1, seg2.start)
  seg.ends <- c(seg2.start-1, n)
  for(seg.i in seq_along(seg.starts)){
    seg.start <- seg.starts[[seg.i]]
    seg.end <- seg.ends[[seg.i]]
    seg.data <- sample.counts[seg.start:seg.end, ]
    seg.mean <- with(seg.data, sum(coverage * weight)/sum(weight))
    mean.mat[model.i, seg.i] <- seg.mean
    seg.loss <- with(seg.data, PoissonLoss(coverage, seg.mean, weight))
    loss.list[[paste(model.i, seg.i)]] <-
      data.table(model.i, seg.i,
                 seg2.chromStart, seg2.start,
                 seg.start, seg.end,
                 seg.chromStart=sample.counts$chromStart[seg.start],
                 seg.chromEnd=sample.counts$chromEnd[seg.end],
                 seg.mean, seg.loss)
  }
}
loss.dt <- do.call(rbind, loss.list)
model.dt <- loss.dt %>%
  group_by(model.i, seg2.chromStart) %>%
  summarise(loss=sum(seg.loss))
model.dt$feasible <-
  ifelse(mean.mat[,1] < mean.mat[,2], "yes", "no")
feasible <- model.dt %>%
  filter(feasible=="yes")

show.models <-
  c(5, 40,
    which.min(model.dt$loss),
    120, 200, 310)
show.loss.list <- split(loss.dt, loss.dt$model.i)
show.model.list <- split(model.dt, model.dt$model.i)
png.list <- list()
last.base <- max(model.dt$seg2.chromStart/1e3)
best.loss <- min(model.dt$loss)
t.dt <- data.table(last.base, best.loss, what="loss")
for(show.model.i in seq_along(show.models)){
  model.i <- show.models[[show.model.i]]
  show.model <- show.model.list[[model.i]]
  show.loss <- show.loss.list[[model.i]]
  selectedPlot <- 
  ggplot()+
  geom_step(aes(chromStart/1e3, coverage),
            data=data.table(sample.counts, what="profile"),
            color="grey50")+
  geom_segment(aes(seg.chromStart/1e3, seg.mean,
                   xend=seg.chromEnd/1e3, yend=seg.mean),
               color="green",
               data=data.frame(show.loss, what="profile"))+
    geom_vline(aes(xintercept=last.base), data=t.dt,
               color="grey")+
    geom_text(aes(last.base, best.loss, label="t "),
              data=t.dt, hjust=1, vjust=0, color="grey")+
  ## geom_line(aes(seg2.chromStart/1e3, loss),
  ##           data=data.table(model.dt, what="loss"))+
  geom_point(aes(seg2.chromStart/1e3, loss, size=feasible),
             data=data.table(model.dt, what="loss"),
             pch=1)+
  geom_point(aes(seg2.chromStart/1e3, loss, size=feasible),
             data=data.table(show.model, what="loss"),
             pch=1,
             color="green")+
  geom_vline(aes(xintercept=seg2.chromStart/1e3),
             data=show.model,
             linetype="dotted",
             color="green")+
  geom_text(aes(seg2.chromStart/1e3,
                max(sample.counts$coverage),
                label="t' "),
             hjust=1,
             vjust=1,
             data=data.table(show.model, what="profile"),
             color="green")+
  scale_size_manual(values=c(yes=2, no=0.5))+
  theme_bw()+
  theme(panel.margin=grid::unit(0, "cm"))+
  facet_grid(what ~ ., scales="free")+
  ylab("")+
  xlab(paste("position on chromosome (kb = kilo bases)"))

  png(png.name <- sprintf("figure-dp-%d.png", show.model.i),
      units="in", res=200, width=6, height=3)
  print(selectedPlot)
  dev.off()

  png.list[[png.name]] <- png.name
}

pngs <- do.call(c, png.list)

png.tex <- sprintf("
\\begin{frame}
\\frametitle{Computation of optimal loss $\\mathcal L_{s, t}$
 for $s=2$ segments up to last data point $t = d$}
  \\includegraphics[width=\\textwidth]{%s}

$$
\\mathcal L_{2, t} =
\\min_{
  t' < t
}
\\underbrace{
  \\mathcal L_{1, t'}
}_{
  \\text{optimal loss in 1 segment up to $t'$}
}
+
\\underbrace{
  c_{(t', t]}
}_{
  \\text{optimal loss of 2nd segment $(t', t]$}
}
$$

\\end{frame}
", pngs)

cat(png.tex, file="figure-dp.tex")
