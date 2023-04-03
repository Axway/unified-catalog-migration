#!/bin/bash

set -x

# Sourcing user-provided env properties
source ./config/env.properties

#jq -n -f ./jq/product-plan-quota.jq --arg product_plan_name "PRODUCT_PLAN_NAME" --arg resource_name "ASSET_NAME/CATALOG_APISERVICE" > ./product-plan-quota.json
jq '.spec.pricing.limit.value=($ENV.PLAN_QUOTA|tonumber)' ./product-plan-quota.json > planB.json

if [[ $CLIENT_ID == "" ]]
  then
    echo "No arguments supplied => login via browser"
	  #axway auth login
  else
	  echo "Service account supplied => login headless"
	  #axway auth login --client-id $1 --secret-file "$2" --username $3
fi

if [[ $PUBLISH_TO_MARKETPLACES == "Y" ]]
then
    # Publishing to the Marketplace(s)
    echo "	Publishing product into Marketplaces..."
fi
	