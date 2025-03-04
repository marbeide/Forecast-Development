# Test/Compare SR models using different software/priors

library(dplyr)
library(ggplot2)
library(TMB)
library(tmbstan)
source("Code/Functions.R")

#================================================================================

# Simulate some basic Ricker data

SimData <- Sim_Ricker_SR_Data(leng=50, age=4, Sig_Ricker = 0.3, true_a = rnorm(1, 5, 2), true_b=1/100000,
                          hr_min = 0.2, hr_max = 0.8, lnorm_corr = FALSE)

SimDataDF <- data.frame(S = round(SimData$S), R = (SimData$R), Year = 1:length(SimData$S))

# Create DF to store true and fitted values
DataDF <- SimDataDF[, c("S", "R", "Year")]
DataDF$Fit <- SimData$true_a * DataDF$S * exp( -SimData$true_b * DataDF$S )
DataDF$Mod <- "True"
DataDF$CI_low <- DataDF$CI_up  <-  DataDF$Pred <- DataDF$Pred_low <- DataDF$Pred_up <- DataDF$Fit

ggplot(data = DataDF, aes(x=S, y=Fit)) +
  geom_line(size = 1.5, col = "red") +
  geom_point(aes(x=S, y=R), col = "black") 

# run using TMB, without prior

# only need to compile if changed model
# dyn.unload(dynlib("Code/TMB/Single_Stock_Ricker"))
# TMB::compile("Code/TMB/Single_Stock_Ricker.cpp") # can't seem to compile if have TMBstan loaded
dyn.load(dynlib("Code/TMB/Single_Stock_Ricker"))

TMB_No_Prior <- RunRicker(Data = SimDataDF, 
                  Fitting_SW = "TMB", 
                  Priors = F, Name = "TMB_No_Prior")

# Now run with priors same as "true" values
TMB_True_Prior <- RunRicker(Data = SimDataDF,  Fitting_SW = "TMB", 
                            Priors = T, Name = "TMB_True_Prior",
                            logA_mean = log(SimData$true_a),
                            logA_sig = 0.5, 
                            Smax_mean = 1/SimData$true_b, 
                            Smax_sig = 1/SimData$true_b/4) 

# Run same model as mcmc using tmbstan
library(tmbstan)
tmbstan_True_Prior <- RunRicker(Data = SimDataDF,  Fitting_SW = "tmbstan", 
                                Priors = T,  Name = "tmbstan_True_Prior",
                                logA_mean = log(SimData$true_a),
                                logA_sig = 0.5, 
                                Smax_mean = 1/SimData$true_b, 
                                Smax_sig = 1/SimData$true_b/4)

# Fit using JAGS
library(R2jags)
JAGS_True_Prior <- RunRicker(Data = SimDataDF,  Fitting_SW = "JAGS", 
                              Priors = T,  Name = "JAGS_True_Prior",
                              logA_mean = log(SimData$true_a),
                              logA_sig = 0.5, 
                              Smax_mean = 1/SimData$true_b, 
                              Smax_sig = 1/SimData$true_b/4)

# Fit using Stan
Stan_True_Prior <- RunRicker(Data = SimDataDF,  Fitting_SW = "Stan", 
                             Priors = T,   Name = "Stan_True_Prior",
                             logA_mean = log(SimData$true_a),
                             logA_sig = 0.5, 
                             Smax_mean = 1/SimData$true_b, 
                             Smax_sig = 1/SimData$true_b/4)

All_Ests <- bind_rows(DataDF, TMB_No_Prior$Fit, TMB_True_Prior$Fit, 
                      tmbstan_True_Prior$Fit, JAGS_True_Prior$Fit,
                      Stan_True_Prior$Fit)

  
# Now plot all to compare 
ggplot(data = All_Ests, aes(x=S, y=Fit, ymin = CI_low, ymax = CI_up, col = Mod, fill= Mod)) +
geom_line(size = 1.5) +
geom_ribbon( alpha = 0.1) +
geom_point(aes(x=S, y=R), col = "black") +
geom_ribbon(aes(x=S, y=Pred, ymin = Pred_low, ymax = Pred_up, fill= Mod), 
            alpha = 0.05) +
theme_bw()
  
# jags and stan predictive intervals are a little bit wider, but pretty similar
# Expect slight difference since TMB approach is pseudo-Bayesian

#===========================================================================
# Also look at posteriors of alpha and beta from each bayesian model?

# compile all posts into DF
Bayes_Mods <- list("tmbstan_True_Prior" = tmbstan_True_Prior, 
                   "JAGS_True_Prior" = JAGS_True_Prior, 
                   "Stan_True_Prior" = Stan_True_Prior)

Posts <- data.frame(A = numeric(), Smax = numeric(),  Mod = character())

for(i in 1:length(Bayes_Mods)){
  New_Rows <- data.frame(A = Bayes_Mods[[i]]$A_Post, Smax = Bayes_Mods[[i]]$Smax_Post,  
                         Mod = names(Bayes_Mods)[[i]])
  Posts <- bind_rows(Posts, New_Rows)
}

# Also Add two tmb estimates
A_No_Prior <- TMB_No_Prior$Ests %>% filter(Param == "A") %>% pull(Estimate)
A_True_Prior <- TMB_True_Prior$Ests %>% filter(Param == "A") %>% pull(Estimate)
  
ggplot(Posts, aes(A, stat(density), col = Mod)) +
  geom_freqpoly() +
  geom_vline(xintercept = A_No_Prior, col = "black") +
  geom_vline(xintercept = A_True_Prior, col = "darkgrey") +
  geom_vline(xintercept = SimData$true_a, linetype = "dashed")+
  theme_bw()

# COmpare Smax estimates

# Also Add two tmb estimates
Smax_No_Prior <- TMB_No_Prior$Ests %>% filter(Param == "Smax") %>% pull(Estimate) * TMB_No_Prior$Scale
Smax_True_Prior <- TMB_True_Prior$Ests %>% filter(Param == "Smax") %>% pull(Estimate) * TMB_True_Prior$Scale


ggplot(Posts, aes(Smax, stat(density), col = Mod)) +
  geom_freqpoly() +
  geom_vline(xintercept = Smax_No_Prior, col = "black") +
  geom_vline(xintercept = Smax_True_Prior, col = "darkgrey") +
  geom_vline(xintercept = 1/SimData$true_b, linetype = "dashed")+
  theme_bw()

# in some cases JAGS estiamtes look slightly different, not sure why?

# hard to return exact param values, but fits are close to true, so projections
# shouldn't be very affected -- maybe that shoudl be the next thing to compare?
