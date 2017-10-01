#!/bin/bash

# I like to use docopt...
hparams_name=$1
inputs_dir=$2
outputs_dir=$3
dst_root=$4
generator_warmup_epoch=$5
discriminator_warmup_epoch=$6
spoofing_total_epoch=$7
total_epoch=$8

randstr=$(python -c "from datetime import datetime; print(str(datetime.now()).replace(' ', '_'))")

echo "Name of hyper paramters:" $hparams_name
echo "Network inputs directory:" $inputs_dir
echo "Network outputs directory:" $outputs_dir
echo "Model checkpoints saved at:" $dst_root
echo "Experiment identifier:" $randstr
echo "Generator wamup epoch:" $generator_warmup_epoch
echo "Discriminator wamup epoch:" $discriminator_warmup_epoch
echo "Total epoch for spoofing model training:" $spoofing_total_epoch
echo "Total epoch for GAN:" $total_epoch

max_files=-1 # -1 means `use full data`.

# Checkpoint naming rule:
# checkpoint_epoch{epoch}_{Generator/Discriminator}.pth

baseline_checkpoint=$dst_root/baseline/checkpoint_epoch${total_epoch}_Generator.pth
spoofing_checkpoint=$dst_root/spoofing/checkpoint_epoch${spoofing_total_epoch}_Discriminator.pth


### Baseline ###

python train.py --hparams_name="$hparams_name" \
    --max_files=$max_files --w_d=0 --hparams="nepoch=$total_epoch"\
    --checkpoint-dir=$dst_root/baseline $inputs_dir $outputs_dir \
    --log-event-path="log/${hparams_name}_baseline_$randstr"


### GAN ###

# Generator warmup
# only train generator
python train.py --hparams_name="$hparams_name" \
    --max_files=$max_files --w_d=0 --hparams="nepoch=$generator_warmup_epoch" \
    --checkpoint-dir=$dst_root/gan_g_warmup $inputs_dir $outputs_dir \
    --log-event-path="log/${hparams_name}_generator_warmup_$randstr"

# Discriminator warmup
# only train discriminator
python train.py --hparams_name="$hparams_name" \
    --max_files=$max_files --w_d=1 \
    --checkpoint-g=$dst_root/gan_g_warmup/checkpoint_epoch${generator_warmup_epoch}_Generator.pth\
    --discriminator-warmup --hparams="nepoch=$discriminator_warmup_epoch" \
    --checkpoint-dir=$dst_root/gan_d_warmup $inputs_dir $outputs_dir \
    --restart_epoch=0 \
    --log-event-path="log/${hparams_name}_discriminator_warmup_$randstr"

# Discriminator warmup for spoofing rate computation
# try to discrimnate baseline's generated features as fake
# only train discriminator
python train.py --hparams_name="$hparams_name" \
    --max_files=$max_files --w_d=1 --hparams="nepoch=$spoofing_total_epoch" \
    --checkpoint-g=${baseline_checkpoint} \
    --discriminator-warmup \
    --checkpoint-dir=$dst_root/spoofing \
    --restart_epoch=0 $inputs_dir $outputs_dir \
    --log-event-path="log/${hparams_name}_spoofing_model_warmup_$randstr"

# Finally do joint training generator and discriminator
# start from ${generator_warmup_epoch}
python train.py --hparams_name="$hparams_name" \
    --max_files=$max_files \
    --checkpoint-d=$dst_root/gan_d_warmup/checkpoint_epoch${discriminator_warmup_epoch}_Discriminator.pth \
    --checkpoint-g=$dst_root/gan_g_warmup/checkpoint_epoch${generator_warmup_epoch}_Generator.pth \
    --checkpoint-r=${spoofing_checkpoint} \
    --w_d=1 --hparams="nepoch=$total_epoch" \
    --checkpoint-dir=$dst_root/gan \
    --restart_epoch=${generator_warmup_epoch} \
    --reset_optimizers $inputs_dir $outputs_dir \
    --log-event-path="log/${hparams_name}_adversarial_training_$randstr"