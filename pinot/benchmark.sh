#!/bin/bash

sudo apt-get update
sudo apt install openjdk-11-jdk jq -y
sudo update-alternatives --config java

# Install

PINOT_VERSION=0.11.0

wget https://downloads.apache.org/pinot/apache-pinot-$PINOT_VERSION/apache-pinot-$PINOT_VERSION-bin.tar.gz
tar -zxvf apache-pinot-$PINOT_VERSION-bin.tar.gz

mkdir tmp

DEBUG_OPTS="
  -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:9050
  -Dcom.sun.management.jmxremote.port=5555
  -Dcom.sun.management.jmxremote.rmi.port=5555
  -Dcom.sun.management.jmxremote.authenticate=false
  -Dcom.sun.management.jmxremote.ssl=false
  -Djava.rmi.server.hostname=127.0.0.1
"

JAVA_OPTS="
  -Xms8G
  -Dlog4j2.configurationFile=conf/log4j2-server.xml
  -Dpinot.admin.system.exit=true
  -Djava.io.tmpdir=$PWD/tmp
  ${DEBUG:+$DEBUG_OPTS}
  " \
  ./apache-pinot-$PINOT_VERSION-bin/bin/pinot-admin.sh \
  QuickStart \
  -type empty \
  -configFile $PWD/conf/config.conf \
  -dataDir $PWD/data &
sleep 30
./apache-pinot-$PINOT_VERSION-bin/bin/pinot-admin.sh AddTable -tableConfigFile offline_table.json -schemaFile schema.json -exec

# Load the data

wget --continue 'https://datasets.clickhouse.com/hits_compatible/hits.tsv.gz'
gzip -dk hits.tsv.gz

# Pinot was unable to load data as a single file without any errors returned. We have to split the data
split -d --additional-suffix .csv --verbose -n l/100 hits.tsv parts

rm hits.tsv

# Pinot can't load value '"tatuirovarki_redmond' so we need to fix this row to make it work
sed parts93.csv -e 's "tatuirovarki_redmond tatuirovarki_redmond g' -i

# Fix path to local directory
cp create-segments.yaml create-segments-customized.yaml
sed 's PWD_DIR_PLACEHOLDER '$PWD' g' -i create-segments-customized.yaml
cp push-segments.yaml push-segments-customized.yaml
sed 's PWD_DIR_PLACEHOLDER '$PWD' g' -i push-segments-customized.yaml

# Translate csv into segments
PINOT_COMPONENT="load_job" JAVA_OPTS="-Xms8G -Dlog4j2.configurationFile=conf/log4j2.xml -Dpinot.admin.system.exit=true -Djava.io.tmpdir=$PWD/tmp" time ./apache-pinot-$PINOT_VERSION-bin/bin/pinot-admin.sh LaunchDataIngestionJob -jobSpecFile create-segments-customized.yaml

rm *.csv

# Push segments
PINOT_COMPONENT="load_job" JAVA_OPTS="-Xms8G -Dlog4j2.configurationFile=conf/log4j2.xml -Dpinot.admin.system.exit=true -Djava.io.tmpdir=$PWD/tmp" time ./apache-pinot-$PINOT_VERSION-bin/bin/pinot-admin.sh LaunchDataIngestionJob -jobSpecFile push-segments-customized.yaml

# Run the queries
./run.sh

# stop Pinot services
kill %1

# Remove the copy of the segments recently pushed
rm -rf data/rawdata/PinotControllerDir0/hits/

du -bcs ./data
