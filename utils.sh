#########################################
# Error management after a command line #
#########################################
function error_exit {
   if [ $? -ne 0 ]
   then
      echo "$1"
      if [ $2 ]
      then
         echo "See $2 file for errors"
      fi
	  error=1
      exit 1
   fi
}

######################################
# Error management after a curl POST #
# $1 = message to display            #
# $2 = file name                     #
######################################
function error_post {
	# search in input file if there are some errors

	if [ $2 ] # safe guard
	then
		errorFound=`cat $2 | jq -r ".errors"`
		if [[ $errorFound != null ]]
		then
			echo "$1. Please check file $2"
			error=1
			exit 1
		fi
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

#################################################
# Creating a product plan unit if non available #
################################################
function create_productplanunit_if_not_exist() {

	# Adding a product plan unit if not exisiting
	export PLAN_UNIT_COUNT=$(axway central get productplanunit -q title=="\"$PLAN_UNIT_NAME\"" -o json | jq '.|length')

	if [ $PLAN_UNIT_COUNT -eq 0 ]
	then
		echo "	Creating new plan unit..."
		jq -n -f ./jq/product-plan-unit.jq --arg name "$PLAN_UNIT_NAME" --arg title "$PLAN_UNIT_NAME" > ./json_files/product-plan-unit.json
		axway central create -f ./json_files/product-plan-unit.json -o json -y > $TEMP_DIR/product-plan-unit-created.json
		error_exit "Problem creating a product plan unit" "$TEMP/product-plan-unit-created.json"
	else 
		echo "	Found existing plan unit: $PLAN_UNIT_NAME"
	fi
}



##########################################################
# Getting data from the marketplace                      #
# either return the entire object or the portion         #
# specified with $2 as a jq extract expression           #
#                                                        #
# $1 (mandatory): url to call                            #
# $2 (optional): jq expression to extract information    #
##########################################################
function getFromMarketplace() {

	if [[ $3 == "" ]]
	then 
		outputFile=getFromMarketplaceResult.json
	else
		outputFile=$3
	fi


	curl -s -k -L $1 -H "Content-Type: application/json" -H "X-Axway-Tenant-Id: $PLATFORM_ORGID" --header 'Authorization: Bearer '$PLATFORM_TOKEN > $outputFile

	if [[ $2 == "" ]]
	then
		echo `cat $outputFile`
	else
		echo `cat $outputFile | jq -r "$2"`
	fi
}

###################################
# Posting data to the marketplace #
# and get the data into a file    #
#                                 #
# $1: url to call                 #
# $2: payload                     #
# $3: output file                 #
###################################
function postToMarketplace() {

	if [[ $3 == "" ]]
	then 
		outputFile=postToMarketplaceResult.json
	else
		outputFile=$3
	fi

	#echo "url for MP = "$1
	curl -s -k -L $1 -H "Content-Type: application/json" -H "X-Axway-Tenant-Id: $PLATFORM_ORGID" --header 'Authorization: Bearer '$PLATFORM_TOKEN -d "`cat $2`" > $outputFile

	cat $outputFile
}

############################################
# Getting the Unified Catalog Documentation
# Always read the 1st revision
# $1: CATALOG_ID
# $2: CATALOG_DESCRIPTION value
#
# Return catalog documention if not null, 
# otherwise the catalog description ($2)
############################################
function readCatalogDocumentationFromItsId() {

	# variable assignment
	CATALOG_ID=$1
	RETURN_VALUE=$2

	# Get catalog documentation property
	URL=$CENTRAL_URL'/api/unifiedCatalog/v1/catalogItems/'$CATALOG_ID'/revisions/1/properties/documentation'
	curl -s --location --request GET ${URL} --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/catalogItemDocumentation.txt

	# remove 1st and last " from the string
	cat $TEMP_DIR/catalogItemDocumentation.txt | cut -d "\"" -f 2 > $TEMP_DIR/catalogItemDocumentationAfterCut.txt
	DOC_TEMP=`cat $TEMP_DIR/catalogItemDocumentationAfterCut.txt`

	# replace \n with newline
	sed 's/\\n/\'$'\n''/g' <<< $DOC_TEMP > $TEMP_DIR/catalogItemDocumentationCleaned.txt
	DOC_TEMP=`cat $TEMP_DIR/catalogItemDocumentationCleaned.txt`

	if [[ $DOC_TEMP != "" ]]
	then
		RETURN_VALUE=$DOC_TEMP
	fi

	echo $RETURN_VALUE
}


################################
# $1: json of catalog items
# $3: consumerInstanceID
# Output: CatalogId
################################
function findCatalogItenAssociatedWithConsumerInstance {

	CATALOG_LIST=$1
	CONSUMER_INSTANCE_ID=$2

	# loop over JSon
	cat $CATALOG_LIST | jq -rc ".[] | {id: .id"} | while IFS= read -r line ; do

		CATALOG_ID=$(echo $line | jq -r '.id')

		# query the CatalogItem properties
		URL=$CENTRAL_URL'/api/unifiedCatalog/v1/catalogItems/'$CATALOG_ID'/properties/apiServerInfo'
		curl -s --location --request GET ${URL} --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/catalogProperties.json

		CONSUMERI_ID_FOUND=`cat $TEMP_DIR/catalogProperties.json | jq -r ".consumerInstance.id"`

		if [ $CONSUMERI_ID_FOUND == $CONSUMER_INSTANCE_ID ]
		then
			echo $CATALOG_ID
			exit 0
		fi

	done
}

###########################################################################
# Read Marketplace Information (guid/url/subdomain)                       #
#                                                                         #
# INPUT: $MARKETPLACE_TITLE                                               #
# OUTPUT: json with:                                                      #
# {"guid": "guidValue", "url": "urlValue", "subdomain": "subDomainValue"} #
###########################################################################
function readMarketplaceInformation {

	# Get MARKETPLACE_URL property
	if [[ $PLATFORM_URL == '' ]]
	then
		# use the default PROD url
		PLATFORM_URL="https://platform.axway.com"	
	fi

	URL=$PLATFORM_URL'/api/v1/provider?org_guid='$PLATFORM_ORGID
	curl -s --location --request GET ${URL} --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/marketplaceList.json
	MP_INFO=`jq --arg FILTER_VALUE "$MARKETPLACE_TITLE" -r '.result[] | select(.name==$FILTER_VALUE)' $TEMP_DIR/marketplaceList.json | jq -rc '{guid: .guid, url: .url, subdomain: .subdomain}'`

	echo $MP_INFO
}

###################################################
# Retrieve the Marketplace guid based on its name #
#                                                 #
# OUTPUT: marketaplce guid                        #
###################################################
function readMarketplaceGuidFromMarketplaceName {
	MP_INFO=$(readMarketplaceInformation)

	MP_GUID=`echo $MP_INFO | jq -rc '.guid'`
	echo $MP_GUID
}

##################################################
# Retrieve the Marketplace URL based on its name #
#                                                #
# OUTPUT: marketaplce url                        #
##################################################
function readMarketplaceUrlFromMarketplaceName {

	MP_INFO=$(readMarketplaceInformation)

	VANITY_URL=`echo $MP_INFO | jq -rc '.url'`

	# is it a vanity url?
	if [[ $VANITY_URL != null ]]
	then 
		# yes
		RESULT=`echo "https://$VANITY_URL"`
	else
		# no, need to build the url based on subdomain and region
		SUBDOMAIN=`echo $MP_INFO | jq -rc '.subdomain'`

		if [[ $MP_EXTENSION == '' ]]
		then
			# uses PROD known values
			if [[ $ORGANIZATION_REGION == 'EU' ]]
			then
				# we are in EU
				RESULT=`echo "https://$SUBDOMAIN.marketplace.eu.axway.com"`
			else 
				if [[ $ORGANIZATION_REGION == 'AP' ]]
				then
					# we are in APAC
					RESULT=`echo "https://$SUBDOMAIN.marketplace.ap-sg.axway.com"`
				else
					# Default US region
					RESULT=`echo "https://$SUBDOMAIN.marketplace.us.axway.com"`
				fi
			fi

		else
			# uses provided extension
			RESULT=`echo "https://$SUBDOMAIN.$MP_EXTENSION"`
		fi

	fi
	echo $RESULT
}

########################################
# Build CentralURl based on the region #
#                                      #
# Input: region                        #
# Output: CENTRAL_URL is set           #
########################################
function getCentralURL {

	if [[ $CENTRAL_URL == '' ]]
	then
		if [[ $ORGANIZATION_REGION == 'EU' ]]
		then
			# we are in France
			CENTRAL_URL="https://central.eu-fr.axway.com"
		else 
			if [[ $ORGANIZATION_REGION == 'AP' ]]
			then
				# we are in APAC
				CENTRAL_URL="https://central.ap-sg.axway.com"
			else
				# Default US region
				CENTRAL_URL="https://apicentral.axway.com"
			fi
		fi
	fi 

	echo $CENTRAL_URL
}

######################################
# Validate the environment variables #
######################################
function checkEnvironmentVariables {
	
	if [[ $CENTRAL_ENVIRONMENT == '' ]]
	then
		echo "CENTRAL_ENVIRONMENT vairable is not set" 
		exit 1
	fi

	if [[ $MARKETPLACE_TITLE == '' ]]
	then
		echo "MARKETPLACE_URL vairable is not set" 
		exit 1
	fi
}


###########################################
#
# Create a plan + quota and activate it
#
# $1 : owner
# $2 : productName
# $3 : consumerInstanceName
# $4 : assetName
# $5 : resourceName
###########################################
function createActiveProductPlan {

	# param mapping
	CONSUMER_INSTANCE_OWNER_ID=$1
	PRODUCT_NAME=$2
	CONSUMER_INSTANCE_NAME=$3
	ASSET_NAME=$4
	RESOURCE_NAME=$5
	ENVIRONMENT_NAME=$6

	# Compute PlanTitle
	PLAN_TITLE="Plan for $ASSET_NAME - $CONSUMER_INSTANCE_NAME - $ENVIRONMENT_NAME"

	if [[ $CONSUMER_INSTANCE_OWNER_ID == null ]]
	then
		echo "		without owner"
		jq -n -f ./jq/product-plan-create.jq --arg plan_title "$PLAN_TITLE" --arg product $PRODUCT_NAME --arg approvalMode $PLAN_APPROVAL_MODE > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-plan.json
	else
		echo "		with owningTeam : $CONSUMER_INSTANCE_OWNER_ID"
		jq -n -f ./jq/product-plan-create-owner.jq --arg plan_title "$PLAN_TITLE" --arg product $PRODUCT_NAME --arg approvalMode $PLAN_APPROVAL_MODE  --arg teamId "$CONSUMER_INSTANCE_OWNER_ID" > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-plan.json
	fi
	axway central create -f $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-plan.json -o json -y > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-plan-created.json
	error_exit "Problem when creating a Product plan" "$TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-plan-created.json"

	# retrieve product plan since there could be naming conflict
	export PRODUCT_PLAN_NAME=`jq -r .[0].name $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-plan-created.json`
	export PRODUCT_PLAN_ID=`jq -r .[0].metadata.id $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-plan-created.json`

	# Adding plan quota
	echo "		Adding plan quota..."
	jq -n -f ./jq/product-plan-quota.jq --arg product_plan_name $PRODUCT_PLAN_NAME --arg unit $PLAN_UNIT_NAME --arg resource_name $ASSET_NAME/$RESOURCE_NAME > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-plan-quota.json
	# update the quota limit - need to put it in the environment list so that jq can access the value.
	PLAN_QUOTA=`echo $PLAN_QUOTA`
	export PLAN_QUOTA
	jq '.spec.pricing.limit.value=($ENV.PLAN_QUOTA|tonumber)' $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-plan-quota.json > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-plan-quota-updated.json
	axway central create -f $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-plan-quota-updated.json -y -o json > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-plan-quota-created.json
	error_exit "Problem with creating Quota" "$TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-plan-quota-created.json"

	# Activating the plan
	echo "	Activating the plan..."
	axway central get productplans $PRODUCT_PLAN_NAME -o json  | jq '.state = "active"' > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-plan-updated.json
	echo $(cat $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-plan-updated.json | jq 'del(. | .status?, .references?)') > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-plan-updated.json
	axway central apply -f $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-plan-updated.json -y > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-plan-activation.json
	error_exit "Problem activating the plan" "$TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-plan-activation.json"
}


###############################################################
# Compute the Asset name base on Catalog item name and version
# CatalogName / X.Y.Z => CatalogName VX
#
# $1: catalog name
# $2: catalog version (X.Y.Z)
###############################################################
function computeAssetNameFromAPIservice {
	CONSUMER_INSTANCE_TITLE=$1
	CATALOG_ITEM_VERION=$2

	if [[ $ASSET_NAME_FOLLOW_SERVICE_VERSION == 'Y' ]] ;
	then
		echo "$1 V"$(printf %.1s "$2")
	else
		echo "$1"
	fi
}

######################################################
# Remove the team name from Application Name
# to have cleaner application in Marketplace
#
# $1 : Unified Catalog subscription application name
# Output: APP_NAME
#
# Sample:  APP_NAME (TeamName) => APP_NAME
######################################################
function removeTeamNameFromApplciationName {
	# remove everything after ( and any ending spaces
	echo $1 | cut -f1 -d"(" | sed -e 's/[[:space:]]*$//'
}