
## Power simulations for Caspi et al 2002, MAOA GxE candidate gene study

library(plyr)
library(broom)
library(magrittr)
library(reshape2)
library(ggplot2)

data <- data.frame(genotype = c("low", "low", "low", "high", "high", "high"),
                   maltreatment = c("no", "probable", "severe", "no", "probable", "severe"),
                   N = c(108, 42, 13, 180, 79, 20),
                   conduct_fraction = c(0.25, 0.35, 0.85, 0.25, 0.3, 0.45))
data$conduct_disorder <- round(data$conduct_fraction * data$N)
data$group <- paste(data$genotype, data$maltreatment)

(odds_population <- sum(data$conduct_disorder)/sum(data$N - data$conduct_disorder))
(p_population <- sum(data$conduct_disorder)/sum(data$N))

(odds_low_severe <- data$conduct_disorder[data$group == "low severe"] /
  (data$N[data$group == "low severe"] - data$conduct_fraction[data$group == "low severe"]))

(odds_high_severe <- data$conduct_disorder[data$group == "high severe"] /
  (data$N[data$group == "high severe"] - data$conduct_fraction[data$group == "high severe"]))


expanded_data <- ddply(data, c("genotype", "maltreatment"), function(x) {
  data.frame(genotype = rep(x$genotype, x$N),
             maltreatment = rep(x$maltreatment, x$N),
             conduct_disorder = c(rep(1, x$conduct_disorder),
                                  rep(0, x$N - x$conduct_disorder)))
})


ddply(subset(expanded_data, maltreatment == "severe"), "genotype", summarise,
      conduct_disorder = sum(conduct_disorder), n = length(genotype))

model <- glm(conduct_disorder ~ genotype * maltreatment,
             expanded_data, family = binomial(link = "logit"))

## Odds ratios

(estimates <- data.frame(exp(cbind(coef(model), confint(model)))))
estimates$coef <- rownames(estimates)
colnames(estimates) <- c("OR", "lower", "upper", "coef")


## Caspi 2002 maltreatment probable 1.3, severe 2.5
## Rautiainen 2016 GWAS 1.6
## Ficks & Waldman 2013 1.2 Metaanalysis of marginal MAOA 

simplified_model <- glm(conduct_disorder ~ genotype,
                        subset(expanded_data, maltreatment == "severe"),
                        family = binomial(link = "logit"))


(simplified_estimates <- exp(cbind(coef(simplified_model), confint(simplified_model))))

simulate_data <- function(OR, intercept, p_low, N) {
  x <- c(rep(0, round(N * (1 - p_low))), rep(1, round(N * p_low)))
  genotype <- ifelse(x == 1, "low", "high")
  z <- intercept + log(OR) * x
  p <- 1/(1 + exp(-z))
  y <- rbinom(N, 1, p) 
  data.frame(genotype, conduct_disorder = y)
}


fake_data <- function(OR, intercept = -0.2, nsim = 1000, p_low = 13/(20+13), N = 20+13) {
  replicate(nsim, simulate_data(OR = OR, intercept = intercept, p_low, N), simplify = FALSE)
}

fake_glms <- function(fake_data) {
  results <- ldply(fake_data, function(x) {
    tidy(glm(conduct_disorder ~ genotype, x, family = binomial(link = "logit")))
  })
  subset(results, term == "genotypelow")
}

power_summary <- function(fake_glms, true_OR) {
  significant <- subset(fake_glms, p.value < 0.05)
  data.frame(power = nrow(significant)/nrow(fake_glms),
             mean_estimate = exp(mean(significant$estimate)),
             sign_error = nrow(subset(significant, exp(estimate) < 1))/nrow(significant))
}


power_simulations <- ldply(seq(from = 1.1, to = 3, by = 0.1),
  function(x) fake_data(x) %>% fake_glms %>% power_summary())
power_simulations$OR <- seq(from = 1.1, to = 3, by = 0.1)


power_plots <- function(power_simulations) {
  list(power_plot = qplot(x = OR, y = power, data = power_simulations) +
         ylim(0, 1) + geom_smooth(se = FALSE) + theme_bw(),
       sign_error_plot = qplot(x = OR, y = sign_error, data = power_simulations) +
         ylim(0, 1) + geom_smooth(se = FALSE) + theme_bw(),
       exaggeration_plot = qplot(x = OR, y = mean_estimate, data = power_simulations) +
         geom_smooth(se = FALSE) + theme_bw())
}

small_power_plots <- power_plots(power_simulations)

large_power_simulations <- ldply(seq(from = 1.1, to = 3, by = 0.1),
  function(x) fake_data(x, nsim = 1000, N = 500) %>%
  fake_glms %>% power_summary())
large_power_simulations$OR <- seq(from = 1.1, to = 3, by = 0.1)


large_power_plots <- power_plots(large_power_simulations)


## Meta-analysis
library(metafor)

fake_meta_data <- fake_data(2, nsim = 15)
fake_meta_summarised <- ldply(fake_meta_data, function(x) {
  data.frame(tpos = sum(x$genotype == "low" & x$conduct_disorder == 1),
             tneg = sum(x$genotype == "low" & x$conduct_disorder == 0),
             cpos = sum(x$genotype == "high" & x$conduct_disorder == 1),
             cneg = sum(x$genotype == "high" & x$conduct_disorder == 0))
})

escalc(measure = "OR", ai = tpos, bi = tneg, ci = cpos,
       di = cneg, data = fake_meta_summarised, append = FALSE) %>% rma
