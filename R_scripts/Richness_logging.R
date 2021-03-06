#######################################################################################
#Script for meta-analysis of changes in species richness with logging##################
#and plots for paper###################################################################
#######################################################################################

#name: Phil Martin
#date:13/04/2015

#clear objects
rm(list=ls())

#open packages
library(ggplot2)
library(metafor)
library(MuMIn)
library(boot)
library(plyr)
library(reshape2)
#and functions needed
Mode <- function(x) {
  ux <- unique(x)
  ux[which.max(tabulate(match(x, ux)))]
}

#import data
Richness<-read.csv("Data/Rich_intens.csv")
head(Richness)

#calculate SDs
#unlogged
Richness$SDU<-ifelse(Richness$VarT=="SE",Richness$V_UL*sqrt(Richness$SS_UL),Richness$V_UL)
Richness$SDU<-ifelse(Richness$VarT=="CI",(Richness$V_UL/1.96)*sqrt(Richness$SS_UL),Richness$SDU)
#logged
Richness$SDL<-ifelse(Richness$VarT=="SE",Richness$V_L*sqrt(Richness$SS_L),Richness$V_L)
Richness$SDL<-ifelse(Richness$VarT=="CI",(Richness$V_L/1.96)*sqrt(Richness$SS_L),Richness$SDL)

Richness2<-subset(Richness,SDL>0)

Richness2$CVL<-Richness2$SDL/Richness2$M_L
Richness2$CVUL<-Richness2$SDU/Richness2$M_UL

plot(Richness2$Plot_size,Richness2$CVL)
plot(Richness2$Plot_size,Richness2$CVUL)

M1_L<-lm(CVL~log(Plot_size),data=Richness2)
M1_UL<-lm(CVUL~log(Plot_size),data=Richness2)


#impute missing standard deviation values
#based on coefficient of variation
#following ideas in Koricheva et al 2013
Richness3<-subset(Richness,Richness$SDU>0)

Richness$SDL<-ifelse(Richness$SDL<0,Richness$M_L*((0.06983+(-0.08769*log(Richness$Plot_size)))),Richness$SDL)
Richness$SDU<-ifelse(Richness$SDU<0,Richness$M_L*((0.06368+(-0.10706*log(Richness$Plot_size)))),Richness$SDU)

#change rarefied column
head(Richness)
Richness$Rare2<-ifelse(Richness$Rare=="Not rarefied","NR",NA)
Richness$Rare2<-ifelse(Richness$Rare=="Rarefied - Area","R",Richness$Rare2)
Richness$Rare2<-ifelse(Richness$Rare=="Rarefied - Individuals","R",Richness$Rare2)
Richness$Rare2<-as.factor(Richness$Rare2)

#calculate the log ratio
ROM<-escalc(data=Richness,measure="ROM",m2i=M_UL,sd2i=SDU,n2i=SS_UL,m1i=M_L,sd1i=SDL,n1i=SS_L,append=T)
ROM$Age<-ifelse(is.na(ROM$Age),mean(ROM$Age,na.rm=T),ROM$Age)




############################################################
#Analysis for studies including volume######################
#accounting for age and survey method diffs#################
############################################################

ROM_vol<-subset(ROM,!is.na(Vol))
ROM_vol<-subset(ROM,Vol!=-9999)
Rich_vol<-subset(ROM_vol,!is.na(vi))
sum(Rich_vol$SS_UL)
sum(Rich_vol$SS_L)

write.csv(Rich_vol,"Data/Richness_studies.csv")

#models of richness change including volume

#standardise volume and age using Zuurs methods
Rich_vol$Vol_std<-(Rich_vol$Vol-mean(Rich_vol$Vol))/sd(Rich_vol$Vol)
Rich_vol$Age_std<-(Rich_vol$Age-mean(Rich_vol$Age))/sd(Rich_vol$Age)

Site_unique<-unique(Rich_vol$M_UL)

Model_AIC_summary<-NULL
for (i in 1:10000){
print(i)
Rich_samp<-NULL
for (j in 1:length(Site_unique)){
  Rich_sub<-subset(Rich_vol,M_UL==Site_unique[j])
  Rich_sub<-Rich_sub[sample(nrow(Rich_sub), 1), ]
  Rich_samp<-rbind(Rich_sub,Rich_samp)
}
Model0_Vol<-rma.mv(yi,vi,mods=~1,random=list(~ 1 | Rare,~ 1| DBH),method="ML",data=Rich_samp)
Model1_Vol<-rma.mv(yi,vi,mods=~Vol_std,random=list( ~ 1 | Rare,~ 1| DBH),method="ML",data=Rich_samp)
Model2_Vol<-rma.mv(yi,vi,mods=~Method,random=list( ~ 1 | Rare,~ 1| DBH),method="ML",data=Rich_samp)
Model3_Vol<-rma.mv(yi,vi,mods=~Age_std,random=list( ~ 1 | Rare,~ 1| DBH),method="ML",data=Rich_samp)
Model_AIC<-data.frame(AICc=c(Model0_Vol$fit.stats$ML[5],Model1_Vol$fit.stats$ML[5],Model2_Vol$fit.stats$ML[5],Model3_Vol$fit.stats$ML[5]))
Model_AIC$Vars<-c("Null","Volume",
                  "Method","Age")
Model_AIC$dev<-c(deviance(Model0_Vol),deviance(Model1_Vol),deviance(Model2_Vol),deviance(Model3_Vol))
Null_log<-deviance(Model0_Vol)
Model_AIC$R2<-1-(Model_AIC$dev/Null_log)
Model_AIC<-Model_AIC[order(Model_AIC$AICc),] #reorder from lowest to highest
Model_AIC$delta<-Model_AIC$AICc-Model_AIC$AICc[1]#calculate AICc delta
Model_AIC$rel_lik<-exp((Model_AIC$AICc[1]-Model_AIC$AICc)/2)#calculate the relative likelihood of model
Model_AIC$weight<-Model_AIC$rel_lik/(sum(Model_AIC$rel_lik))
Model_AIC$Run<-i
Model_AIC$Rank<-seq(1,4,1)
Model_AIC_summary<-rbind(Model_AIC,Model_AIC_summary)
}

head(Model_AIC_summary)
Model_AIC_summary$Rank1<-ifelse(Model_AIC_summary$Rank==1,1,0)

summary(Model_AIC_summary)
Model_sel_boot<-ddply(Model_AIC_summary,.(Vars),summarise,Prop_rank=sum(Rank1)/10000,AICc_med=median(AICc),
      delta_med=median(delta),R2_med=median(R2))

write.table(Model_sel_boot,file="Tables/Rich_vol_model_sel.csv",sep=",")


#re-run top model using REML
#bootstrapping 10,000 times to get estimates

Site_unique<-unique(Rich_vol$M_UL)
Param_boot<-NULL
for (i in 1:10000){
  print(i)
  Rich_samp<-NULL
  for (j in 1:length(Site_unique)){
    Rich_sub<-subset(Rich_vol,M_UL==Site_unique[j])
    Rich_sub<-Rich_sub[sample(nrow(Rich_sub), 1), ]
    Rich_samp<-rbind(Rich_sub,Rich_samp)
  }
  Model1_Vol<-rma.mv(yi,vi,mods=~Vol,random=list(~ 1 | Rare,~ 1| DBH),method="REML",data=Rich_samp)
  Param_vals<-data.frame(Parameter=c("Intercept","Vol_slope"),estimate=coef(summary(Model1_Vol))[1],se=coef(summary(Model1_Vol))[2],
             pval=coef(summary(Model1_Vol))[4],ci_lb=coef(summary(Model1_Vol))[5],ci_ub=coef(summary(Model1_Vol))[6])
  Param_boot<-rbind(Param_vals,Param_boot)
}

Param_boot_sum<-ddply(Param_boot,.(Parameter),summarise,coef_estimate=median(estimate),lower=median(ci.lb),
      upper=median(ci.ub),med_pval=median(pval),se=median(se))

write.table(Param_boot_sum,file="Tables/Rich_parameter_estimates.csv",sep=",")

summary(Rich_vol$Vol)
#create dataframe for predictions
newdat<-data.frame(Vol=seq(5.7,122.6,length.out=500))
newdat$yi<-Param_boot_sum$coef_estimate[1]+(newdat$Vol*Param_boot_sum$coef_estimate[2])
newdat$UCI<-(Param_boot_sum$upper[1])+(Param_boot_sum$upper[2]*newdat$Vol)
newdat$LCI<-(Param_boot_sum$lower[1])+(Param_boot_sum$lower[2]*newdat$Vol)

write.csv(newdat,"Data/Preds_Richness.csv",row.names=F)

######################################################
#start here just to plot the figure###################
######################################################

#plot results
#first create x axis labels
Vol_ax<-(expression(paste("Volume of wood logged (",m^3,ha^-1,")")))
theme_set(theme_bw(base_size=16))
vol_plot<-ggplot(newdat,aes(x=Vol,y=exp(yi)-1,ymax=UCI,ymin=LCI))+geom_ribbon(alpha=0.2)+geom_line(size=2)
vol_plot2<-vol_plot+geom_point(data=Rich_vol,aes(ymax=NULL,ymin=NULL,colour=Method,size=1/vi),shape=1)
vol_plot3<-vol_plot2+ylab("Proportional change in tree \nspecies richness following logging")
vol_plot4<-vol_plot3+scale_size_continuous(range=c(5,10))+geom_hline(y=0,lty=2,size=1)
vol_plot5<-vol_plot4+theme(panel.grid.major = element_blank(),panel.grid.minor = element_blank(),panel.border = element_rect(size=1.5,colour="black",fill=NA))
vol_plot6<-vol_plot5+xlab(expression(paste("Volume of wood logged (",m^3,ha^-1,")")))+scale_colour_brewer(palette="Set1")
rich_vol_plot<-vol_plot6+theme(legend.position="none")+scale_colour_brewer(palette="Set1")
rich_vol_plot
ggsave("Figures/SR_volume.png",height=5,width=7,dpi=1200)


