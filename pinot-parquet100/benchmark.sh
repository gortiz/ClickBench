#!/bin/bash

sudo apt-get update
sudo apt install openjdk-11-jdk jq -y
sudo update-alternatives --config java

# Install

PINOT_VERSION=0.10.0

wget https://downloads.apache.org/pinot/apache-pinot-$PINOT_VERSION/apache-pinot-$PINOT_VERSION-bin.tar.gz
tar -zxvf apache-pinot-$PINOT_VERSION-bin.tar.gz

./apache-pinot-$PINOT_VERSION-bin/bin/pinot-admin.sh QuickStart -type empty -dataDir $PWD/data &
sleep 30
./apache-pinot-$PINOT_VERSION-bin/bin/pinot-admin.sh AddTable -tableConfigFile offline_table.json -schemaFile schema.json -exec

# Load the data
mkdir -p parquet
seq 0 99 | xargs -P100 -I{} bash -c 'test -f parquet/hits_{}.parquet || wget --continue https://datasets.clickhouse.com/hits_compatible/athena_partitioned/hits_{}.parquet -P parquet'

# Pinot can't load value '"tatuirovarki_redmond' so we need to fix this row to make it work
# sed parts*.tsv -e 's "tatuirovarki_redmond tatuirovarki_redmond g' -i

# Fix path to local directory
sed splitted.yaml 's PWD_DIR_PLACEHOLDER '$PWD' g' -i
sed local.yaml 's PWD_DIR_PLACEHOLDER '$PWD' g' -i

# Load data
./apache-pinot-$PINOT_VERSION-bin/bin/pinot-admin.sh LaunchDataIngestionJob -jobSpecFile parquet100.yaml

# After upload it shows 94465149 rows instead of 99997497 in the dataset

# Run the queries
./run.sh

# stop Druid services
kill %1

du -bcs ./data
