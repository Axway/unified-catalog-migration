#!/bin/bash

# TODO: 
# - add owner of Asset / Product & Plan based on the service owner.
# - add the sharing of catalog?
# - catalog documentation?


# Sourcing user-provided env properties
source ./config/env.properties

TEMP_FILE=objectToMigrate.json
TEMP_DIR=./json_files

####################################
# Utility function                 #
####################################
function error_exit {
   if [ $? -ne 0 ]
   then
      echo "$1"
      if [ $2 ]
      then
         echo "See $2 file for errors"
      fi
      exit 1
   fi
}

#####################################
# Creating a stage if non available #
#####################################
function create_stage_if_not_exist() {

	# Adding a stage if not exisiting
	export STAGE_COUNT=$(axway central get stages -q title=="\"$STAGE_TITLE\"" -o json | jq '.|length')

	if [ $STAGE_COUNT -eq 0 ]
	then
		echo "	Creating new Stage..."
		jq -n -f ./jq/stage.jq --arg stage_title "$STAGE_TITLE" --arg stage_description "$STAGE_DESCRIPTION" > ./json_files/stage.json
		axway central create -f ./json_files/stage.json -o json -y > $TEMP_DIR/stage-created.json
		export STAGE_NAME=$(jq -r .[0].name $TEMP_DIR/stage-created.json)
		error_exit "Problem creating a Stage" "$TEMP/stage-created.json"
	else 
		export STAGE_NAME=$(axway central get stages -q title=="\"$STAGE_TITLE\"" -o json | jq -r .[0].name)
		echo "	Found existing stage: $STAGE_NAME"
	fi
}


########################
# TESTING PURPOSE CURL #
########################
function test() {
	CATALOG_NAME="SpaceX Graphql APIs"
	#CATALOG_NAME="RollADice (Stage: Demo)"
	#CATALOG_NAME="Parties"

	echo "	Reading Catalog documentation"
	articleContent=$(readCatalogDocumentation "$CATALOG_NAME")
	echo $articleContent
	echo "end fct"


	# read catalog id from catalog name
#	echo "	Reading associted catalog item"
	# query format section: query=(name==VALUE) -> replace ( and ) by their respective HTML value
#	URL=$CENTRAL_URL'/api/unifiedCatalog/v1/catalogItems?query=%28name==%27'$CATALOG_NAME'%27%29' 
	# replace blanc with %20
#	URL=${URL// /%20}
	#echo "url="$URL
	#echo "curl --location --request GET ${URL} --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN"
#	curl -s --location --request GET ${URL} --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/catalogItem.json
#	CATALOG_ID=`cat $TEMP_DIR/catalogItem.json | jq -r ".[0] | .id"`

	# Get catalog revisions
#	echo "	Reading associated revision...."
#	URL=$CENTRAL_URL'/api/unifiedCatalog/v1/catalogItems/'$CATALOG_ID'/revisions'
#	curl -s --location --request GET ${URL} --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/catalogItemRevisions.json

	# Get catalog documentation
#	echo "	Reading associated doc properties...."
#	URL=$CENTRAL_URL'/api/unifiedCatalog/v1/catalogItems/'$CATALOG_ID'/revisions/1/properties/documentation'
#	curl -s --location --request GET ${URL} --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/catalogItemProperties.json
	# remove 1st and last " from the string
#	export CATALOG_DOCUMENTATION=`cat $TEMP_DIR/catalogItemProperties.json | cut -d "\"" -f 2`
#	echo $CATALOG_DOCUMENTATION


	# Get catalog relationship
#	echo "	Reading associated relationships...."
#	URL=$CENTRAL_URL'/api/unifiedCatalog/v1/catalogItems/'$CATALOG_ID'/relationships'
#	curl -s --location --request GET ${URL} --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/catalogItemRelationships.json

#	echo "	Reading associated ACTIVE subscription...."
#	curl -s --location --request GET $CENTRAL_URL'/api/unifiedCatalog/v1/catalogItems/'$CATALOG_ID'/subscriptions?query=%28state==ACTIVE%29' --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/subscriptions.json
#	echo "	Found " `cat $TEMP_DIR/subscriptions.json | jq '.|length'` " subscription(s)"
}


function readCatalogDocumentation() {

	# variable assignment
	CATALOG_NAME=$1

	# Get the catalog item
	# query format section: query=(name==VALUE) -> replace ( and ) by their respective HTML value
	URL=$CENTRAL_URL'/api/unifiedCatalog/v1/catalogItems?query=%28name==%27'$CATALOG_NAME'%27%29' 
	# replace blanc with %20
	URL=${URL// /%20}
	#echo "url="$URL
	curl -s --location --request GET ${URL} --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/catalogItem.json
	CATALOG_ID=`cat $TEMP_DIR/catalogItem.json | jq -r ".[0] | .id"`

	# Get catalog documentation property
	URL=$CENTRAL_URL'/api/unifiedCatalog/v1/catalogItems/'$CATALOG_ID'/revisions/1/properties/documentation'
	curl -s --location --request GET ${URL} --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/catalogItemProperties.json
	# remove 1st and last " from the string
	echo `cat $TEMP_DIR/catalogItemProperties.json | cut -d "\"" -f 2`
	#echo `cat $TEMP_DIR/catalogItemProperties.json`
}


####################################################
# Creating asset and product based on Catalog Items
# Input parameters:
# 1- Platform Oragnization ID
# 2- Platform Bearer token
# 3- Stage name
####################################################
function create_asset_product() {

mkdir $TEMP_DIR

# map parameters
PLATFORM_ORGID=$1
PLATFORM_TOKEN=$2
STAGE_NAME=$3

# create the applicationList
echo "Reading all Unified Catalog items..."
# TODO - uncomment for real life env.
#axway central get consumeri -o json > $TEMP_DIR/$TEMP_FILE
#CB test only 1 UC
axway central get consumeri -q name==spacex -o json > $TEMP_DIR/$TEMP_FILE
error_exit "Cannot read catalog items"

echo "Found " `cat $TEMP_DIR/$TEMP_FILE | jq '.|length'` " catalog items to migrate."

# loop over the result and keep interesting data (name / description / API Service / Tags / Environment)
cat $TEMP_DIR/$TEMP_FILE | jq -rc ".[] | {id: .metadata.id, name: .name, title: .title, description: .spec.description, apiservice: .references.apiService, tags: .tags, environment: .metadata.scope.name}" | while IFS= read -r line ; do

	# read organization name for creating the corresponding team name
	CATALOG_ID=$(echo $line | jq -r '.id')
	CATALOG_NAME=$(echo $line | jq -r '.name')
	CATALOG_TITLE=$(echo $line | jq -r '.title')
	CATALOG_DESCRIPTION=$(echo $line | jq -r '.description')
	CATALOG_APISERVICE=$(echo $line | jq -r '.apiservice')
	CATALOG_APISERVICEENV=$(echo $line | jq -r '.environment')
	CATALOG_TAGS=$(echo $line | jq -r '.tags')

	echo "Migrating $CATALOG_NAME..."
	#echo "Catalog name: $CATALOG_NAME / $CATALOG_TITLE / $CATALOG_DESCRIPTION / apiService=$CATALOG_APISERVICE"
	
	echo "	Reading corresponding API Service: $CATALOG_APISERVICE"
	axway central get apis $CATALOG_APISERVICE -s $CATALOG_APISERVICEENV -o json > $TEMP_DIR/apis-$CATALOG_APISERVICEENV-$CATALOG_APISERVICE.json
	error_exit "Cannot read catalog item - api service"
	
	export CATALOG_APISERVICE_ICON=`cat $TEMP_DIR/apis-$CATALOG_APISERVICEENV-$CATALOG_APISERVICE.json | jq -r ". | .spec.icon.data" `

	#TODO - check if asset already exist to protect from executing twice or more
	#echo "Reading all Assets items in the organization $PLATFORM_ORGID ..."
	#axway central get assets -q metadata.references.name=="$CATALOG_APISERVICE" -o json > ./json_files/assets.json
	#if [ -s ./json_files/assets.json ]; then
		# The file is not-empty.
		#echo "Assets exists, nothing to do"
	#else
		# Process.
	#fi

	# creating asset in Central
	echo "	creating asset file..."
	jq -n -f ./jq/asset.jq --arg title "$CATALOG_TITLE" --arg description "$CATALOG_DESCRIPTION" > $TEMP_DIR/asset-$CATALOG_NAME.json
    error_exit "Problem when creating asset file" "$TEMP_DIR/asset-$CATALOG_NAME.json"

	# adding tags .... TODO
	echo "	SKIP - adding asset tags..."
	#jq -n -f ./jq/asset.jq --arg title "$CATALOG_TITLE" --arg description "$CATALOG_DESCRIPTION" --arg encodedImage "$CATALOG_IMAGE" --arg tags "$CATALOG_TAGS" > ./json_files/asset.json

	echo "	adding asset icon..."
	echo $(cat $TEMP_DIR/asset-$CATALOG_NAME.json | jq '.icon = "data:image/png;base64," + env.CATALOG_APISERVICE_ICON') > $TEMP_DIR/asset-$CATALOG_NAME.json

	echo "	Posting asset to Central..."
	axway central create -f $TEMP_DIR/asset-$CATALOG_NAME.json -o json -y > $TEMP_DIR/asset-$CATALOG_NAME-created.json
	error_exit "Problem when posting asset icon"

	# retrieve asset name since there could be naming conflict
	export ASSET_NAME=$(jq -r .[0].name $TEMP_DIR/asset-$CATALOG_NAME-created.json)

	# adding the mapping to the service
	echo "	Creating asset mapping for linking with API service..." 
	jq -n -f ./jq/asset-mapping.jq --arg asset_name "$ASSET_NAME" --arg stage_name "$STAGE_NAME" --arg env_name "$CATALOG_APISERVICEENV" --arg srv_name "$CATALOG_APISERVICE" > $TEMP_DIR/asset-$CATALOG_NAME-mapping.json
	echo "	Posting asset mapping to Central"
	axway central create -f $TEMP_DIR/asset-$CATALOG_NAME-mapping.json -y -o json > $TEMP_DIR/asset-$CATALOG_NAME-mapping-created.json
	error_exit "Problem creating asset mapping" "$TEMP_DIR/asset-$CATALOG_NAME-mapping-created.json"

	# reading asset resource name (used for quota creation)
	echo "	Reading the created resource name..."
	 export RESOURCE_NAME=`axway central get assetresource -s $ASSET_NAME -o json | jq -r .[].name`

	# create the corresponding product
	echo "	creating product file..." 
	jq -n -f ./jq/product.jq --arg product_title "$CATALOG_TITLE" --arg asset_name "$ASSET_NAME" --arg description "$CATALOG_DESCRIPTION" > $TEMP_DIR/product-$CATALOG_NAME.json

	echo "	adding product icon..."
	echo $(cat $TEMP_DIR/product-$CATALOG_NAME.json | jq '.icon = "data:image/png;base64," + env.CATALOG_APISERVICE_ICON') > $TEMP_DIR/product-$CATALOG_NAME.json

	echo "	Posting product to Central..."
	axway central create -f $TEMP_DIR/product-$CATALOG_NAME.json -y -o json > $TEMP_DIR/product-$CATALOG_NAME-created.json
	error_exit "Problem creating product" "$TEMP_DIR/product-$CATALOG_NAME-created.json"

	# retrieve product name since there could be naming conflict
	export PRODUCT_NAME=`jq -r .[0].name $TEMP_DIR/product-$CATALOG_NAME-created.json`

	# Create Documentation
	echo "	Adding Documentation..." 
	echo "		Creating article..."
	export articleTitle="Unified Catalog doc"
	#export articleContent=$(<./jq/doc_content.md)
	articleContent=$(readCatalogDocumentation "$CATALOG_TITLE")
	export articleContent
	jq -f ./jq/article.jq $TEMP_DIR/product-$CATALOG_NAME-created.json > $TEMP_DIR/product-$CATALOG_NAME-article.json
	axway central create -f $TEMP_DIR/product-$CATALOG_NAME-article.json -o json -y > $TEMP_DIR/product-$CATALOG_NAME-article-created.json
	export ARTICLE_NAME_1=`jq -r .[0].name $TEMP_DIR/product-$CATALOG_NAME-article-created.json`

	error_exit "Problem creating an article" "$TEMP_DIR/product-$CATALOG_NAME-article-created.json"
	echo "		Creating Document..."
	export docTitle="Product Overview"
	axway central get resources -s $PRODUCT_NAME -q name==$ARTICLE_NAME_1 -o json > $TEMP_DIR/product-$CATALOG_NAME-available-articles.json
	jq -f ./jq/document.jq $TEMP_DIR/product-$CATALOG_NAME-available-articles.json > $TEMP_DIR/product-$CATALOG_NAME-document.json
	axway central create -f $TEMP_DIR/product-$CATALOG_NAME-document.json -o json -y > $TEMP_DIR/product-$CATALOG_NAME-document-created.json
	error_exit "Problem creating a product document" "$TEMP_DIR/product-$CATALOG_NAME-document-created.json"

	#  Create a Product Plan (Free)
	echo "	Adding Free plan..." 
	jq -n -f ./jq/product-plan.jq --arg plan_name free-$PRODUCT_NAME --arg plan_title "$PLAN_TITLE" --arg product $PRODUCT_NAME > $TEMP_DIR/product-$CATALOG_NAME-plan.json
	axway central create -f $TEMP_DIR/product-$CATALOG_NAME-plan.json -o json -y > $TEMP_DIR/product-$CATALOG_NAME-plan-created.json
	error_exit "Problem when creating a Product plan" "$TEMP_DIR/product-$CATALOG_NAME-plan-created.json"

	# retrieve product plan since there could be naming conflict
	export PRODUCT_PLAN_NAME=`jq -r .[0].name $TEMP_DIR/product-$CATALOG_NAME-plan-created.json`

	# Adding plan quota
	echo "	Adding plan quota..."
	jq -n -f ./jq/product-plan-quota.jq --arg product_plan_name $PRODUCT_PLAN_NAME --arg resource_name $ASSET_NAME/$RESOURCE_NAME > $TEMP_DIR/product-$CATALOG_NAME-plan-quota.json
	# update the quota limit
	jq '.spec.pricing.limit.value=($ENV.PLAN_QUOTA|tonumber)' $TEMP_DIR/product-$CATALOG_NAME-plan-quota.json > $TEMP_DIR/product-$CATALOG_NAME-plan-quota-updated.json
	axway central create -f $TEMP_DIR/product-$CATALOG_NAME-plan-quota-updated.json -y -o json > $TEMP_DIR/product-$CATALOG_NAME-plan-quota-created.json
	error_exit "Problem with creating Quota" "$TEMP_DIR/product-$CATALOG_NAME-plan-quota-created.json"

	# Activating the plan
	echo "	Activating the plan..."
	axway central get productplans $PRODUCT_PLAN_NAME -o json  | jq '.state = "active"' > $TEMP_DIR/product-$CATALOG_NAME-plan-updated.json
	echo $(cat $TEMP_DIR/product-$CATALOG_NAME-plan-updated.json | jq 'del(. | .status?, .references?)') > $TEMP_DIR/product-$CATALOG_NAME-plan-updated.json
	axway central apply -f $TEMP_DIR/product-$CATALOG_NAME-plan-updated.json -y > $TEMP_DIR/product-$CATALOG_NAME-plan-activation.json
	error_exit "Problem actovating the plan" "$TEMP_DIR/product-$CATALOG_NAME-plan-activation.json"

	# do we need to publish to the marketpalces?
	if [[ $PUBLISH_TO_MARKETPLACES == "Y" ]]
	then
		# Publishing to the Marketplace(s)
		echo "	Publishing product into Marketplaces..."
		echo "		Read Marketplaces...."
		axway central get marketplaces -o json > $TEMP_DIR/marketplace.json

		#loop for each Marketplace
		cat $TEMP_DIR/marketplace.json | jq -rc ".[] | {name: .name}" | while IFS= read -r lineMp ; do

			# read the marketplace name
			MARKETPLACE_NAME=$(echo $lineMp | jq -r '.name')
			
			echo "		Publishing $PRODUCT_NAME to Marketplace $MARKETPLACE_NAME..."
			#jq --slurp -f ./jq/product-publish.jq $TEMP_DIR/marketplace.json $TEMP_DIR/product-$CATALOG_NAME-created.json  > $TEMP_DIR/product-$CATALOG_NAME-publish.json
			jq -n -f ./jq/product-publish.jq --arg marketplace_name $MARKETPLACE_NAME --arg product_name $PRODUCT_NAME > $TEMP_DIR/product-$CATALOG_NAME-publish.json
			axway central create -f $TEMP_DIR/product-$CATALOG_NAME-publish.json -o json -y > $TEMP_DIR/product-$CATALOG_NAME-publish-created.json
			error_exit "Problem with pubishing a Product on Marketplace" "$TEMP_DIR/product-$CATALOG_NAME-publish-created.json"
			echo "		$PRODUCT_NAME published to Marketplace $MARKETPLACE_NAME"
		done

		##########
		# WARNING: Consumerinstance != Catalog item - only the name can link both
		##########

		# read catalog id from catalog name
		echo "	Finding associted catalog item..."
		# query format section: query=(name==VALUE) -> replace ( and ) by their respective HTML value
		URL=$CENTRAL_URL'/api/unifiedCatalog/v1/catalogItems?query=%28name==%27'$CATALOG_NAME'%27%29' 
		# replace spaces with %20 in case the Catalog name has some
		URL=${URL// /%20}
		curl -s --location --request GET ${URL} --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/catalogItem.json
		CATALOG_ID=`cat $TEMP_DIR/catalogItem.json | jq -r ".[0] | .id"`

		echo "	Reading associated subscription(s)...."
		curl -s --location --request GET $CENTRAL_URL'/api/unifiedCatalog/v1/catalogItems/'$CATALOG_ID'/subscriptions?query=%28state==ACTIVE%29' --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/catalogItemSubscriptions.json
		echo "	Found " `cat $TEMP_DIR/catalogItemSubscriptions.json | jq '.|length'` " ACTIVE subscription(s)"

		# loop on subscription
		#cat $TEMP_DIR/catalogItemSubscriptions.json | jq -rc ".[] | {id: .metadata.id name: .name, title: .title, description: .spec.description, apiservice: .references.apiService, tags: .tags, environment: .metadata.scope.name}" | while IFS= read -r line ; do
	fi
#	done
	
	# clean up current loop...
	echo "	cleaning temp files..."
	#rm $TEMP_DIR/apis-$CATALOG_APISERVICEENV-$CATALOG_APISERVICE.json
	#rm $TEMP_DIR/asset-$CATALOG_NAME*.json
	#rm $TEMP_DIR/asset-mapping-$CATALOG_NAME.json
	#rm $TEMP_DIR/product-$CATALOG_NAME*.json
	#rm $TEMP_DIR/product-plan*.json
	#rm $TEMP_DIR/product-publish*.json
	#rm $TEMP_DIR/catalogItems*.json
	#rm $TEMP_DIR/catalogItemSubscriptions*.json

   exit 1
done

#clean up catalog item files
#rm $TEMP_DIR/$TEMP_FILE

}


#########
# Main
#########

echo ""
echo "======================================================================================" 
echo "== Migrating Unified Catalog object and subsription into Asset/Product/Subscription ==" 
echo "== curl and jq programs are required                                                =="
echo "======================================================================================" 
echo ""

echo "Checking pre-requisites (axway CLI, curl and jq)"
# check that axway CLI is installed
if ! command -v axway &> /dev/null
then
    error_exit "axway CLI could not be found. Please be sure you can run axway CLI on this machine"
fi

#check that curl is installed
if ! command -v curl &> /dev/null
then
    error_exit "curl could not be found. Please be sure you can run curl command on this machine"
fi

#check that jq is installed
if ! command -v jq &> /dev/null
then
    error_exit "jq could not be found. Please be sure you can run jq command on this machine"
fi
echo "All pre-requisites are available" 

#login to the platform
echo ""
echo "Connecting to Amplify platform with Axway CLI"
if [[ $CLIENT_ID == "" ]]
  then
    echo "No client id supplied => login via browser"
	axway auth login
  else
	echo "Service account supplied => login headless"
	axway auth login --client-id $1 --secret-file "$2" --username $3
fi
error_exit "Problem with authentication to your account. Please, verify your credentials"

# retrieve the organizationId of the connected user
echo ""
echo "Retrieving the organization ID..."
PLATFORM_ORGID=$(axway auth list --json | jq -r '.[0] .org .id')
PLATFORM_TOKEN=$(axway auth list --json | jq -r '.[0] .auth .tokens .access_token ')
echo "Done"

#echo ""
#echo "running test only"
#test

echo ""
echo "Preparing a stage if not available"
create_stage_if_not_exist
echo "Done."

echo ""
echo "Migrating Unified Catalog items into Asset and Product"
create_asset_product $PLATFORM_ORGID $PLATFORM_TOKEN $STAGE_NAME
echo "Done."

exit 0