#!/bin/bash

if [ "$#" -ne 3 ] 
  then
    echo "Usage : sh run_test_pipeline.sh <gcp project> <gcp region> <port>"
    exit -1
fi

PROJECT=$1
REGION=$2
PORT=$3

# terminate previously started expansion service instances
PIDS=$(pgrep -a -f "Python.*apache_beam.runners.portability.expansion_service_main" 2>&1) || true

if [ $PIDS != "true" ]; then 
  kill $PIDS
fi


python3 -m apache_beam.runners.portability.expansion_service_main \
--port $PORT \
--fully_qualified_name_glob "*" \
--environment_type="DOCKER" \
--environment_config=gcr.io/$PROJECT/$REGION/beam-embeddings &

EXP_SERVICE_PID=$(echo $!)
