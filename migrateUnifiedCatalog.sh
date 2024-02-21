#!/bin/bash

# TODO: 
# - add the sharing of catalog?

# Sourcing user-provided env properties
source ./config/env.properties

# add all utility functions
source ./utils.sh

TEMP_FILE=catalogItemToMigrate.json
TEMP_DIR=./json_files
error=0

####################################################
# Creating asset and product based on Catalog Items
# Input parameters:
# 1- Platform Oragnization ID
# 2- Platform Bearer token
# 3- catalog item name to migrate (optional)
####################################################
function migrate() {

	mkdir $TEMP_DIR

	# map parameters
	PLATFORM_ORGID=$1
	PLATFORM_TOKEN=$2
	INPUT_TITLE=$3

	# Should we migrate all or just one?
	if [[ $INPUT_TITLE == '' ]]
	then
		# migrate everything from given environment
		echo "Reading all Unified Catalog items..."
		axway central get consumeri -s $CENTRAL_ENVIRONMENT -o json > $TEMP_DIR/$TEMP_FILE
	else
		# migrate a single entity
		echo "Reading $INPUT_TITLE Unified Catalog item from its title..."
		axway central get consumeri -q "title=='$INPUT_TITLE'" -s $CENTRAL_ENVIRONMENT -o json > $TEMP_DIR/$TEMP_FILE
	fi
	error_exit "Cannot read catalog items"

	echo "Found " `cat $TEMP_DIR/$TEMP_FILE | jq '.|length'` " catalog items to migrate."

	# loop over the result and keep interesting data (name / description / API Service / Tags / Environment / Owner)
	cat $TEMP_DIR/$TEMP_FILE | jq -rc ".[] | {id: .metadata.id, name: .name, title: .title, version: .spec.version, apiserviceName: .references.apiService, apiserviceRevision: .references.apiServiceRevision, tags: .tags, environment: .metadata.scope.name, ownerId: .owner.id}" | while IFS= read -r line ; do

		CONSUMER_INSTANCE_ID=$(echo $line | jq -r '.id')
		CONSUMER_INSTANCE_NAME=$(echo $line | jq -r '.name')
		CONSUMER_INSTANCE_TITLE=$(echo $line | jq -r '.title')
		CONSUMER_INSTANCE_VERSION=$(echo $line | jq -r '.version')
		CONSUMER_INSTANCE_OWNER_ID=$(echo $line | jq -r '.ownerId')
		CATALOG_APISERVICE=$(echo $line | jq -r '.apiserviceName')
		CATALOG_APISERVICE_REVISION=$(echo $line | jq -r '.apiserviceRevision')
		CATALOG_APISERVICEENV=$(echo $line | jq -r '.environment')

		echo "Migrating $CONSUMER_INSTANCE_TITLE catalog item..."
		echo "Catalog name: $CONSUMER_INSTANCE_NAME / $CONSUMER_INSTANCE_TITLE / apiService=$CATALOG_APISERVICE / apiServiceRevision=$CATALOG_APISERVICE_REVISION"
		
		# Finding corresponding Unified Catalog - multple catalog can have same name but only one is linked to the consumerInstance using the latestVersion attribute
		echo "	Finding catalog item details..."
		echo "		Finding ID..."
		# query format section: query=(name=='VALUE') -> replace ( and ) by their respective HTML value
		CENTRAL_URL=$(getCentralURL)
		URL=$CENTRAL_URL'/api/unifiedCatalog/v1/catalogItems?query=%28name==%27'$CONSUMER_INSTANCE_TITLE'%27%29' 
		# replace spaces with %20 in case the Catalog name has some
		URL=${URL// /%20}
		curl -s --location --request GET ${URL} --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/catalogItem.json

		# Are there multiple version?
		if [[ `jq length $TEMP_DIR/catalogItem.json` == 1 ]]
		then
			CATALOG_ID=`jq -r ".[0].id" $TEMP_DIR/catalogItem.json`
		else
			#filter the one that match the consumerInstance ID
			CATALOG_ID=$(findCatalogItenAssociatedWithConsumerInstance $TEMP_DIR/catalogItem.json "$CONSUMER_INSTANCE_ID")
		fi
		echo "			CatalogID=$CATALOG_ID"

		if [[ $CATALOG_ID == null ]]
		then
			echo " /!\ error while retrieving the CATALOG_ID."
			exit 1
		fi

		# read catalog details
		URL=$CENTRAL_URL'/api/unifiedCatalog/v1/catalogItems/'$CATALOG_ID'?embed=image,properties,revisions,subscription,categories' 
		curl -s --location --request GET ${URL} --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/catalogItemDetails.json

		echo "		Finding icon..."
		CATALOG_ICON=`cat $TEMP_DIR/catalogItemDetails.json | jq -r "._embedded.image.base64"`
		if [[ $CATALOG_ICON != null ]]
		then
			echo "			Icon found."
			CATALOG_ICON_CONTENT="data:image/png;base64,"$CATALOG_ICON
			# building manually to avoid issue with big image and command line being too short.
			CATALOG_ICON_CONTENT="{\"icon\": \"$CATALOG_ICON_CONTENT\"}"

			echo "			Creating icon json file for later."
			echo $CATALOG_ICON_CONTENT > $TEMP_DIR/asset-product-$CONSUMER_INSTANCE_NAME-icon.json
			error_exit "Error while creating icon file $TEMP_DIR/asset-product-$CONSUMER_INSTANCE_NAME-icon.json"
		fi

		echo "		Finding documentation..."
		CATALOG_DESCRIPTION=`cat $TEMP_DIR/catalogItemDetails.json | jq -r ".description"`
		# replace \n with newline
		sed 's/\\n/\'$'\n''/g' <<< $CATALOG_DESCRIPTION > $TEMP_DIR/catalogItemDescriptionCleaned.txt
		CATALOG_DESCRIPTION=`cat $TEMP_DIR/catalogItemDescriptionCleaned.txt`
		CATALOG_DOCUMENTATION=$(readCatalogDocumentationFromItsId "$CATALOG_ID" $CATALOG_DESCRIPTION)

		echo "		Finding categories..."
		CATALOG_CATEGORIES=""

		cat $TEMP_DIR/catalogItemDetails.json | jq -r "._embedded.categories[].externalId" > $TEMP_DIR/catalogItemCategoryId.txt

		if [ -s $TEMP_DIR/catalogItemCategoryId.txt ]; then
			# file exist and is not empty
			i=0
			# for  each Id, find the category name	
			while read -r catId ; do
				CAT_ID=`axway central get category -q "metadata.id==$catId" -o json | jq  ".[].name"`

				if [[ $i == 0 ]]
				then
					CATALOG_CATEGORIES=$CAT_ID
					i=$(( i + 1 ))
				else
					TMP=$CATALOG_CATEGORIES","$CAT_ID
					CATALOG_CATEGORIES=$TMP
				fi

			done < $TEMP_DIR/catalogItemCategoryId.txt
			echo "			categories found = $CATALOG_CATEGORIES"
		else
			echo "			no categories found!"
		fi

		# Compute the Asset name based on the APIService version: APISErvice version == X.Y.Z => Asset name == APIService name VX
		CATALOG_ITEM_VERION=`cat $TEMP_DIR/catalogItemDetails.json | jq -r ".latestVersion" `
		ASSET_TITLE=$(computeAssetNameFromAPIservice $CONSUMER_INSTANCE_TITLE $CATALOG_ITEM_VERION)

		# Name for the resource viaible in the Marketplace: ServiceName - EnvironmentName
		# TODO could become a function to let the user decide what to do?
		ASSET_RESOURCE_TITLE="$CATALOG_APISERVICE - $CATALOG_APISERVICEENV"

		echo "	Checking if asset $ASSET_TITLE already created..."
		axway central get assets -q "title=='$ASSET_TITLE'" -o json > $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME-exist.json
		# file will never be empty but only contain [] if nothing found.
		if [ `jq length $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME-exist.json` != 0 ]; then
			# The file is empty.
			echo "		Assets exists, need to add new service?"
			# keep information
			export ASSET_NAME=$(jq -r .[0].name $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME-exist.json)

			# check if Asset contain already the service
			axway central get assetresource -s $ASSET_NAME -q metadata.references.name==$CATALOG_APISERVICE_REVISION -o json > $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME-resources-exist.json
			if [ `jq length $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME-resources-exist.json` == 0 ]
			then
				# add asset mapping
				echo "			Creating asset mapping for linking with API service..." 
				
				jq -n -f ./jq/asset-mapping.jq --arg asset_name "$ASSET_NAME" --arg env_name "$CATALOG_APISERVICEENV" --arg srv_name "$CATALOG_APISERVICE" --arg assetResourceTitle "$ASSET_RESOURCE_TITLE" > $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME-mapping.json
				echo "	Posting asset mapping to Central"
				axway central create -f $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME-mapping.json -y -o json > $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME-mapping-created.json
				error_exit "Problem creating asset mapping" "$TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME-mapping-created.json"

				# /!\ this trigger a new release of the product
				export NEED_TO_ADD_PLAN=1
			else
				echo "			Asset already linked with API service - nothing to do"
				export NEED_TO_ADD_PLAN=0	
			fi
		else
			# Process.
			echo "		Asset does not exist, we can create it"

			# creating asset in Central
			echo "	creating asset file..."
			if [[ $CONSUMER_INSTANCE_OWNER_ID == null ]]
			then
				echo "		without owner"
				jq -n -f ./jq/asset-create.jq --arg title "$ASSET_TITLE" --arg description "$CATALOG_DESCRIPTION" > $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME.json
				error_exit "Error while creating asset file $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME.json"
			else
				echo "		with owningTeam : $CONSUMER_INSTANCE_OWNER_ID"
				jq -n -f ./jq/asset-create-owner.jq --arg title "$ASSET_TITLE" --arg description "$CATALOG_DESCRIPTION" --arg teamId "$CONSUMER_INSTANCE_OWNER_ID"> $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME.json
				error_exit "Error while creating asset file $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME.json"
			fi

			# adding tags .... TODO
			echo "	SKIP - adding asset tags..."
			#jq -n -f ./jq/asset.jq --arg title "$CONSUMER_INSTANCE_TITLE" --arg description "$CONSUMER_INSTANCE_DESCRIPTION" --arg encodedImage "$CATALOG_IMAGE" --arg tags "$CATALOG_TAGS" > $TEMP_DIR/asset.json

			# adding icon
			if [[ $CATALOG_ICON != null ]]
			then
				echo "	merging icon with asset content..."
				jq -s '.[0] as $a | .[1] as $b | $a * $b' $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME.json $TEMP_DIR/asset-product-$CONSUMER_INSTANCE_NAME-icon.json  > $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME-tmp.json
				mv $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME-tmp.json $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME.json
			fi

			echo "	Posting asset to Central..."
			axway central create -f $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME.json -o json -y > $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME-created.json
			error_exit "Problem when posting asset icon"

			# retrieve asset name since there could be naming conflict
			export ASSET_NAME=$(jq -r .[0].name $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME-created.json)

			# adding the mapping to the service
			echo "	Creating asset mapping for linking with API service..." 
			jq -n -f ./jq/asset-mapping.jq --arg asset_name "$ASSET_NAME" --arg env_name "$CATALOG_APISERVICEENV" --arg srv_name "$CATALOG_APISERVICE" --arg assetResourceTitle "$ASSET_RESOURCE_TITLE" > $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME-mapping.json
			echo "	Posting asset mapping to Central"
			axway central create -f $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME-mapping.json -y -o json > $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME-mapping-created.json
			error_exit "Problem creating asset mapping" "$TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME-mapping-created.json"
		fi # asset exist?

		# reading asset resource name (used for quota creation)
		echo "	Reading the created asset resource name..."
		export RESOURCE_NAME=`axway central get assetresource -s $ASSET_NAME -q metadata.references.name==$CATALOG_APISERVICE_REVISION -o json | jq -r '.[].name'`


		# Do the same for product but not for subscription... It could help to solve Mercadona duplicate issues: https://jira.axway.com/browse/APIGOV-25743
		echo "	Checking if product $CONSUMER_INSTANCE_TITLE already created..."
		axway central get products -q "title=='$CONSUMER_INSTANCE_TITLE'" -o json > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-exist.json

		# file will never be empty but only contain [] if nothing found.
		if [ `jq length $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-exist.json` != 0 ]
		then
			export PRODUCT_NAME=`jq -r .[0].name $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-exist.json`

			# The file is not empty.
			echo "		Product exists, check Asset already linked?"

			axway central get products -q "title=='$CONSUMER_INSTANCE_TITLE';metadata.references.name=="$ASSET_NAME";metadata.references.kind==Asset" -o json > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-exist-with-asset.json
			if [ `jq length $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-exist-with-asset.json` == 0 ] 
			then
				echo "		Asset not linked ==> linking Asset to product"
				jq -n -f ./jq/product-asset.jq --arg asset_name "$ASSET_NAME" > $TEMP_DIR/product-asset-$CONSUMER_INSTANCE_NAME-add.json
				# merge the files
				jq '.[].spec.assets += [input]' $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-exist.json $TEMP_DIR/product-asset-$CONSUMER_INSTANCE_NAME-add.json > $TEMP_DIR/product-asset-$CONSUMER_INSTANCE_NAME-tmp.json

				# remove waht needs to be removed....
				echo $(cat $TEMP_DIR/product-asset-$CONSUMER_INSTANCE_NAME-tmp.json | jq 'del(. | .[].state?, .[].metadata.references?, .[].references, .[].latestrelease?)') > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-updated.json

				# post to central
				axway central apply -f $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-updated.json -y -o json > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME.json
				error_exit "Problem posting product asset list update" "$TEMP_DIR/product-$CONSUMER_INSTANCE_NAME.json"

				# activate the product
				jq -n -f ./jq/product-activation.jq --arg productName $PRODUCT_NAME > $TEMP_DIR/product-asset-$CONSUMER_INSTANCE_NAME-activate.json
				axway central apply -f $TEMP_DIR/product-asset-$CONSUMER_INSTANCE_NAME-activate.json -y -o json > $TEMP_DIR/product-asset-$CONSUMER_INSTANCE_NAME-activated.json
				error_exit "Problem whie activating product release" "$TEMP_DIR/product-asset-$CONSUMER_INSTANCE_NAME-activated.json"

				# add specific plan for the current resource.
				createActiveProductPlan "$CONSUMER_INSTANCE_OWNER_ID" "$PRODUCT_NAME" "$CONSUMER_INSTANCE_NAME" "$ASSET_NAME" "$RESOURCE_NAME" "$CATALOG_APISERVICEENV"

			else
				echo "		Asset already linked to product => nothing to do"
				# check if Asset Release changed if yes add the plan with new resource.
				if [[ $NEED_TO_ADD_PLAN == 1 ]]
				then
					echo "			Create the new plan for the new resource"
					createActiveProductPlan "$CONSUMER_INSTANCE_OWNER_ID" "$PRODUCT_NAME" "$CONSUMER_INSTANCE_NAME" "$ASSET_NAME" "$RESOURCE_NAME" "$CATALOG_APISERVICEENV"

					# activate the product
					echo "			Activate product"
					jq -n -f ./jq/product-activation.jq --arg productName $PRODUCT_NAME > $TEMP_DIR/product-asset-$CONSUMER_INSTANCE_NAME-activate.json
					axway central apply -f $TEMP_DIR/product-asset-$CONSUMER_INSTANCE_NAME-activate.json -y -o json > $TEMP_DIR/product-asset-$CONSUMER_INSTANCE_NAME-activated.json
					error_exit "Problem whie activating product release" "$TEMP_DIR/product-asset-$CONSUMER_INSTANCE_NAME-activated.json"

					export NEED_TO_ADD_PLAN=0
				fi

			fi
		else
			# Process.
			echo "		Product does not exist, we can create it"

			# create the corresponding product
			echo "	creating product file..." 
			if [[ $CONSUMER_INSTANCE_OWNER_ID == null ]]
			then
				echo "		without owner"
				jq -n -f ./jq/product-create.jq --arg product_title "$CONSUMER_INSTANCE_TITLE" --arg asset_name "$ASSET_NAME" --arg description "$CATALOG_DESCRIPTION" > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME.json
				error_exit "Error while creating product file $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME.json"
			else
				echo "		with owningTeam : $CONSUMER_INSTANCE_OWNER_ID"
				jq -n -f ./jq/product-create-owner.jq --arg product_title "$CONSUMER_INSTANCE_TITLE" --arg asset_name "$ASSET_NAME" --arg description "$CATALOG_DESCRIPTION"  --arg teamId "$CONSUMER_INSTANCE_OWNER_ID" > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME.json
				error_exit "Error while creating product file $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME.json"
			fi

			# adding categories
			if [[ $CATALOG_CATEGORIES != "" ]]
			then
				echo "		Add categories..."
				# add the values into a file based on jq template (jq --arg does not work well with variable as it removes the " surondings the string)
				sed "s/__CAT_LIST__/$CATALOG_CATEGORIES/g" ./jq/category.jq > $TEMP_DIR/pdtCategories.json
				# merge it with product
				jq -s '.[0] as $a | .[1] as $b | $a * $b' $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME.json $TEMP_DIR/pdtCategories.json  > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-category.json
				cp $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-category.json $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME.json
			fi 

			# adding icon
			if [[ $CATALOG_ICON != null ]]
			then
				echo "	merging icon with product content..."
				jq -s '.[0] as $a | .[1] as $b | $a * $b' $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME.json $TEMP_DIR/asset-product-$CONSUMER_INSTANCE_NAME-icon.json  > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-tmp.json
				mv $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-tmp.json $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME.json
			fi

			# adding tags
			if [[ `cat $TEMP_DIR/catalogItemDetails.json | jq -r ".tags"` != "[]" ]]
			then
				# replace the default tags: "Migrated from Unified Catalog" with the one coming from the Unified Catalog item.
				echo "	adding product tags..."
				jq --slurpfile file2 $TEMP_DIR/catalogItemDetails.json '(.tags = $file2[0].tags)' $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME.json > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-tmp.json 
				mv $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-tmp.json $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME.json
			fi

			echo "	Posting product to Central..."
			axway central create -f $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME.json -y -o json > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-created.json
			error_exit "Problem creating product" "$TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-created.json"

			# retrieve product name since there could be naming conflict
			export PRODUCT_NAME=`jq -r .[0].name $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-created.json`

			# Create Documentation
			if [[ CATALOG_DOCUMENTATION != "" ]]
			then
				echo "	Adding product Documentation..." 
				echo "		Creating article..."
				export articleTitle="Unified Catalog doc"
				articleContent=$CATALOG_DOCUMENTATION
				export articleContent
				jq -f ./jq/article.jq $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-created.json > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-article.json
				axway central create -f $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-article.json -o json -y > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-article-created.json
				export ARTICLE_NAME_1=`jq -r .[0].name $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-article-created.json`

				error_exit "Problem creating an article" "$TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-article-created.json"
				echo "		Creating Document..."
				export docTitle="Product Overview"
				axway central get resources -s $PRODUCT_NAME -q name==$ARTICLE_NAME_1 -o json > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-available-articles.json
				jq -f ./jq/document.jq $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-available-articles.json > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-document.json
				axway central create -f $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-document.json -o json -y > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-document-created.json
				error_exit "Problem creating a product document" "$TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-document-created.json"
			fi

			#activate product
			echo "	Releasing the product..." 
			jq -n -f ./jq/product-activation.jq --arg productName $PRODUCT_NAME > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-activation.json
			axway central axwayaxway central create -f $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-activation.json -o json -y > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-activation-created.json
			error_exit "Problem activating product" "$TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-activation-created.json"

			#  Create a Product Plan (Free)
			echo "	Adding Free plan..." 
			createActiveProductPlan "$CONSUMER_INSTANCE_OWNER_ID" "$PRODUCT_NAME" "$CONSUMER_INSTANCE_NAME" "$ASSET_NAME" "$RESOURCE_NAME" "$CATALOG_APISERVICEENV"

		fi # product exist?

		# do we need to publish to the marketpalces?
		if [[ $PUBLISH_TO_MARKETPLACES == "Y" ]]
		then

			# read Marketplace URL
			MP_URL=$(readMarketplaceUrlFromMarketplaceName)
			MP_GUID=$(readMarketplaceGuidFromMarketplaceName)

			if [[ $MP_GUID == "" ]]
			then
				echo "/!\ Marketplace $MARKETPLACE_TITLE not found... We cannot publish the product nor migrate Unified Catalog subscription(s)." 
			else

				echo "	Checking that $CONSUMER_INSTANCE_TITLE is not already published to $MARKETPLACE_TITLE..."
				# check the product is not already published for this Marketplace
				axway central get publishedproduct -s $MP_GUID -q "metadata.references.name=="$PRODUCT_NAME";metadata.references.kind==product" -o json > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-published.json

				if [ `jq length $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-published.json` == 0 ]
				then
					echo "		Publishing $CONSUMER_INSTANCE_NAME to Marketplace $MARKETPLACE_TITLE ($MP_GUID)..."
					if [[ $CONSUMER_INSTANCE_OWNER_ID == null ]]
					then
						echo "		without owner"
						jq -n -f ./jq/product-publish-create.jq --arg marketplace_name $MP_GUID --arg product_name $PRODUCT_NAME > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-publish.json
					else
						echo "		with owningTeam : $CONSUMER_INSTANCE_OWNER_ID"
						jq -n -f ./jq/product-publish-create-owner.jq --arg marketplace_name $MP_GUID --arg product_name $PRODUCT_NAME  --arg teamId "$CONSUMER_INSTANCE_OWNER_ID" > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-publish.json
					fi
					axway central create -f $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-publish.json -o json -y > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-publish-created.json
					error_exit "Problem with pubishing a Product on Marketplace" "$TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-publish-created.json"
					echo "		$PRODUCT_NAME published to Marketplace $MARKETPLACE_TITLE"
				fi

				##########
				# WARNING: Consumerinstance != Catalog item - only the AcatlogItem/properties.apiServerInfor.consumerInstance link them
				##########

				# read catalog item subscriptions ACTIVE / CHANGE_REQUESTED => query=state=in=(ACTIVE,CHANGE_REQUESTED)
				echo "	Reading associated Unified Catalog subscription(s)...."
				curl -s --location --request GET $CENTRAL_URL'/api/unifiedCatalog/v1/catalogItems/'$CATALOG_ID'/subscriptions?query=state=in=%28ACTIVE,CHANGE_REQUESTED%29' --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/catalogItemSubscriptions.json
				echo "	Found " `cat $TEMP_DIR/catalogItemSubscriptions.json | jq '.|length'` " ACTIVE or CHANGE_REQUESTED subscription(s)"

				# loop on subscription
				cat $TEMP_DIR/catalogItemSubscriptions.json | jq -rc ".[] | {subId: .id, subName: .name, teamId: .owningTeamId, appName: .properties[0].value.appName, ownerId: .metadata.createUserId}" | while IFS= read -r line ; do
					# read subscriptionId, application name, teamId and subscription name
					SUBSCRIPTION_ID=$(echo $line | jq -r '.subId')
					UC_SUBSCRIPTION_NAME=$(echo $line | jq -r '.subName')
					UC_SUBSCRIPTION_OWNING_TEAM=$(echo $line | jq -r '.teamId')
					UC_SUBSCRIPTION_OWNER_ID=$(echo $line | jq -r '.ownerId')
					UC_APPLICATION_NAME=$(echo $line | jq -r '.appName')

					echo "		Need to migrate subscription ($UC_SUBSCRIPTION_NAME) for team ($UC_SUBSCRIPTION_OWNING_TEAM) using application ($UC_APPLICATION_NAME) to marketplace ($MARKETPLACE_TITLE)"

					echo "			Searching product id in marketplace..."
					# replace space with %20
					SANITIZE_CATALOG_NAME=${CONSUMER_INSTANCE_TITLE// /%20}
					getMarketplaceProductFromCatalogItem $SANITIZE_CATALOG_NAME "$TEMP_DIR/product-mp-$SANITIZE_CATALOG_NAME.json"

					MP_PRODUCT_ID=`cat  $TEMP_DIR/product-mp-$SANITIZE_CATALOG_NAME.json | jq -r ' .[0].id'`
					MP_PRODUCT_VERSION_ID=`cat  $TEMP_DIR/product-mp-$SANITIZE_CATALOG_NAME.json | jq -r ' .[0].latestVersion.id'`
					echo "			Found product id in marketplace: $MP_PRODUCT_ID"
					echo "			Found product latest version id in marketplace: $MP_PRODUCT_VERSION_ID"

					echo "			Search the PlanId that manage the current service..."
					MP_PRODUCT_PLAN_ID=$(getMarketplaceProductPlanIdFromCatalogItem "$ASSET_RESOURCE_TITLE" $CONSUMER_INSTANCE_VERSION $MP_PRODUCT_ID $MP_PRODUCT_VERSION_ID "$ASSET_TITLE")
					echo "			Found PlanId: $MP_PRODUCT_PLAN_ID"	

					echo "			Search if a susbcription exits for that plan..."
					# it is forbidden for the same team to have 2 subsctiptions on the same plan
					# 1st check that we have subscriptions
					# we assume subscription does not exist yet
					NEED_TO_CREATE_SUBSCRIPTION=1
					# can we or not add access - we cannot when using the same susbcription/resource with multiple apps.
					CAN_CREATE_ACCESS_REQUEST=1
					# read MP subscription attached to the product
					# base on team.
					#getFromMarketplace "$MP_URL/api/v1/subscriptions?product.id=$MP_PRODUCT_ID&owner.id=$UC_SUBSCRIPTION_OWNING_TEAM" "" "$TEMP_DIR/product-mp-$SANITIZE_CATALOG_NAME-subscriptions.json"
					# with x-private, the team filter is not interesting.
					getFromMarketplace "$MP_URL/api/v1/subscriptions?product.id=$MP_PRODUCT_ID" "" "$TEMP_DIR/product-mp-$SANITIZE_CATALOG_NAME-subscriptions.json"
					NB_SUBSCRIPTION=`cat $TEMP_DIR/product-mp-$SANITIZE_CATALOG_NAME-subscriptions.json | jq -r '.totalCount'`

					if [[ $NB_SUBSCRIPTION != 0 ]]
					then
						# we can search within the list
						echo "				Subscription list not empty, do we already have one subscription for team $UC_SUBSCRIPTION_OWNING_TEAM and planId..."
						export MP_SUBSCRIPTION_ID=`cat $TEMP_DIR/product-mp-$SANITIZE_CATALOG_NAME-subscriptions.json | jq '[ .items[] | select( .plan.id=="'$MP_PRODUCT_PLAN_ID'" and .owner.id=="'$UC_SUBSCRIPTION_OWNER_ID'" ) ]' | jq -r '.[0].id'`

						# subscription not found?
						if [[ $MP_SUBSCRIPTION_ID == null ]]
						then
							echo "				Cannot find subscription in existing one -> need to create a new subscription"
							# the susbcription does not exist and we need to create a new one.
							NEED_TO_CREATE_SUBSCRIPTION=1
						else
							echo "				Found existing subscription=$MP_SUBSCRIPTION_ID"
							NEED_TO_CREATE_SUBSCRIPTION=0

							if [[ $PLAN_QUOTA == 'unlimited' ]]
							then
								echo "				Unlimited quota allows to be able to create further access request"
								CAN_CREATE_ACCESS_REQUEST=1
							else
								echo "				/!\ Only one subscription at a time for Free plan.... -> will not be able to create further access request"
								CAN_CREATE_ACCESS_REQUEST=0
							fi
						fi
					fi

					if [[ $NEED_TO_CREATE_SUBSCRIPTION == 1 ]]
					then
						echo "				Creating subscription..."
						UC_SUBSCRIPTION_NAME="UC - Subscription for $CATALOG_APISERVICE - $CATALOG_APISERVICEENV"
						echo "				New Subscription name: $UC_SUBSCRIPTION_NAME for user >>>"

						echo "				Posting susbcription creation..."
						jq -n -f ./jq/product-mp-subscription-private.jq --arg subscriptionTitle "$UC_SUBSCRIPTION_NAME" --arg teamId $UC_SUBSCRIPTION_OWNING_TEAM --arg planId $MP_PRODUCT_PLAN_ID --arg productId $MP_PRODUCT_ID --arg userGuid $UC_SUBSCRIPTION_OWNER_ID > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-subscription-$SUBSCRIPTION_ID.json
						postToMarketplace "$MP_URL/api/v1/subscriptions" $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-subscription-$SUBSCRIPTION_ID.json $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-subscription-$SUBSCRIPTION_ID-created.json
						error_post "Problem creating subscription on Marketplace." $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-subscription-$SUBSCRIPTION_ID-created.json
						# read the subscriptionId from the created susbcription
						export MP_SUBSCRIPTION_ID=`cat $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-subscription-$SUBSCRIPTION_ID-created.json | jq -r ".id"`
					fi

					# Now, time to create application and access request
					if [[ $UC_APPLICATION_NAME == null ]]
					then
						echo "			/!\ no application found, cannot create ManagedApplication / AccessRequest"
					else
						echo "			Unified Catalog application exist, need to create Marketplace application -> remove the team name from UC application name"
						# appName (team) -> appName
						MP_APPLICATION_NAME=$(removeTeamNameFromApplicationName "$UC_APPLICATION_NAME")
						MP_APPLICATION_NAME_TMP=${MP_APPLICATION_NAME// /-}
						MP_APPLICATION_NAME_SANITIZED=${MP_APPLICATION_NAME_TMP//\//-}

						# check if managedapp not already exists to avoid duplicating it
						echo "				is $MP_APPLICATION_NAME exist on the Marketplace?"
						getFromMarketplace "$MP_URL/api/v1/applications?limit=10&offset=0&search=${MP_APPLICATION_NAME// /%20}&sort=-metadata.modifiedAt%2C%2Bname" "" "$TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-applications-search.json"
						MP_APPLICATION_ID=`cat $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-applications-search.json | jq -r '.items[0].id'`

						if [[ $MP_APPLICATION_ID == "null" ]]
						then
							# application does not exist yet... so we can create it
							echo "					Create MP application $MP_APPLICATION_NAME...."
							jq -n -f ./jq/product-mp-application-private.jq --arg applicationTitle "$MP_APPLICATION_NAME" --arg teamId $UC_SUBSCRIPTION_OWNING_TEAM --arg userGuid $UC_SUBSCRIPTION_OWNER_ID > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-application-$MP_APPLICATION_NAME_SANITIZED.json
							postToMarketplace "$MP_URL/api/v1/applications" $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-application-$MP_APPLICATION_NAME_SANITIZED.json $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-application-$MP_APPLICATION_NAME_SANITIZED-created.json
							error_post "Problem creating application on Marketplace." $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-application-$MP_APPLICATION_NAME_SANITIZED-created.json
							export MP_APPLICATION_ID=`cat $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-application-$MP_APPLICATION_NAME_SANITIZED-created.json | jq -r ".id"`
						else
							echo "					$MP_APPLICATION_NAME application is already existing."
						fi

						# Now we need to check that we have all elements to create the access request ie CRD/ARD otherwise it will fails
						# read apisr and check ARD/CRD presence
						axway central get apisi -q "metadata.references.name==$CATALOG_APISERVICE&sort=metadata.audit.createTimestamp%2CDESC" -s $CATALOG_APISERVICEENV -o json > $TEMP_DIR/apis-$CATALOG_APISERVICEENV-$CATALOG_APISERVICE-instance.json
						# retrieve ARD / CRD....
						cat $TEMP_DIR/apis-$CATALOG_APISERVICEENV-$CATALOG_APISERVICE-instance.json | jq -rc ".[0] | {ard: .spec.accessRequestDefinition, crd: .spec.credentialRequestDefinitions}" > $TEMP_DIR/apis-$CATALOG_APISERVICEENV-$CATALOG_APISERVICE-instance-check.json
						ARD=`cat $TEMP_DIR/apis-$CATALOG_APISERVICEENV-$CATALOG_APISERVICE-instance-check.json | jq -rc ".ard"`
			
						if [[ $ARD != null ]]
						then
							echo "			Check if access request exists...."
							ACCESS_REQUEST_NAME="$MP_APPLICATION_NAME"

							MP_ASSETRESOURCE_ID=$(getMarketplaceProductAssetResourceIdFromCatalogItem "$ASSET_RESOURCE_TITLE" "$CONSUMER_INSTANCE_VERSION" "$MP_PRODUCT_ID" "$MP_PRODUCT_VERSION_ID" "$ASSET_TITLE")
							# Is access request already existing?
							ACCESS_REQUEST_EXISTS=$(isAccessRequestAlreadyExisting "$MP_PRODUCT_ID" "$MP_ASSETRESOURCE_ID" "$ACCESS_REQUEST_NAME" "$MP_SUBSCRIPTION_ID" "$MP_APPLICATION_ID")

							if [[ $ACCESS_REQUEST_EXISTS == 0 ]]
							then
								# Access Request does not exist, we can create it
								echo "			Access request does not exist -> creating it...."

								# WARNING HERE: 
								# - we cannot anymore accessing Resouce via 2 differents application under the same Susbcription
								# - free plan does not allow multiple subscriptions

								if [[ $CAN_CREATE_ACCESS_REQUEST == 1 ]]
								then
									# we can add the access
									jq -n -f ./jq/product-mp-accessrequest.jq --arg accessRequestTile "$ACCESS_REQUEST_NAME" --arg productId "$MP_PRODUCT_ID" --arg productIdVersion "$MP_PRODUCT_VERSION_ID" --arg assetResourceId "$MP_ASSETRESOURCE_ID" --arg subscriptionId $MP_SUBSCRIPTION_ID > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-application-$MP_APPLICATION_ID-access.json
									postToMarketplace "$MP_URL/api/v1/applications/$MP_APPLICATION_ID/accessRequests" $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-application-$MP_APPLICATION_ID-access.json $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-application-$MP_APPLICATION_ID-access-created.json
									error_post "Problem creating application access on Marketplace." $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-application-$MP_APPLICATION_ID-access-created.json

									# read id 
									ACCESS_REQUEST_ID=`cat $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-application-$MP_APPLICATION_ID-access-created.json | jq -r '.id'`

									echo "			Mark access request $ACCESS_REQUEST_NAME status as susccess...."
									# change status of the accessrequest from Pending to Success

									MP_ACCESSREQUEST_NAME=`cat $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-application-$MP_APPLICATION_ID-access-created.json | jq -r ".title"`
									markAccessRequestStatusAsSuccess "$CATALOG_APISERVICEENV" "$MP_ACCESSREQUEST_NAME" $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-accessrequest-$ACCESS_REQUEST_ID-statusUpdated.json
									error_post "Problem activating access request." $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-accessrequest-$ACCESS_REQUEST_ID-statusUpdated.json

									# ManagedApp is created only when the AccessRequest is...
									echo "			Mark managed application $MP_APPLICATION_NAME status as Success...."
									# change status of the app from Pending to Success
									# find the managed app
									MANAGEDAPP_TITLE=`axway central get managedapp -s $CATALOG_APISERVICEENV -q "title=='$MP_APPLICATION_NAME'" -o json | jq -r '.[0].title'`

									if [[ $MANAGEDAPP_TITLE != null ]]
									then
										MANAGEDAPP_TITLE_WITHOUT_SPACE=${MANAGEDAPP_TITLE// /-}
										MANAGEDAPP_TITLE_SANITIZED=${MANAGEDAPP_TITLE_WITHOUT_SPACE//\//-}

										markManagedAppStatusAsSuccess "$CATALOG_APISERVICEENV" "$MANAGEDAPP_TITLE" "$TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-application-$MANAGEDAPP_TITLE_SANITIZED-statusUpdated.json"
										error_post "Problem activating application." $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-application-$MANAGEDAPP_TITLE_SANITIZED-statusUpdated.json
									fi
								else
									echo "			/!\ Cannot add access to $MP_APPLICATION_NAME using subscription $UC_SUBSCRIPTION_NAME : access already exist for another application"
								fi
							fi

							# TODO - Manage Credentials? => Impossible without Gateway connectivity
							#CRD=`cat $TEMP_DIR/apis-$CATALOG_APISERVICEENV-$CATALOG_APISERVICE-instance-check.json | jq -rc ".crd"`
						else
							echo "			/!\ Cannot proceed with AccessRequest as the service does not have the CredentialRequestDefinition nor the AccessRequestDefinition"
						fi
					fi

				done # loop over subscription
			fi # Marektplace exists

		fi # Publish to Marketplace
		
		# clean up current loop if no error happened...
		echo "	cleaning temp files..."
		if [[ $error == 0 ]] # does not work all the time as we set the error inside a loop /!\
		then
			echo "clean 1"
			rm $TEMP_DIR/*$CONSUMER_INSTANCE_NAME*
		fi

	done # loop over catalog items

	# clean up catalog item files
	if [[ $error == 0 ]]
	then
		echo "clean 2"
		rm $TEMP_DIR/catalog*
		rm $TEMP_DIR/*arketplace*
		rm $TEMP_DIR/pdtCategories.json
	fi

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

# check environment variables
checkEnvironmentVariables
echo "All mandatory variables are set" 

#login to the platform
echo ""
echo "Connecting to Amplify platform with Axway CLI"
if [[ $CLIENT_ID == "" ]]
  then
    echo "No client id supplied => login via browser"
	axway auth login
  else
	echo "Service account supplied => login headless"
	axway auth login --client-id $CLIENT_ID --secret-file "$CLIENT_SECRET"
fi
error_exit "Problem with authentication to your account. Please, verify your credentials"

# retrieve the organizationId of the connected user
echo ""
echo "Retrieving the organization ID..."
PLATFORM_ORGID=$(axway auth list --json | jq -r '.[0] .org .id')
PLATFORM_TOKEN=$(axway auth list --json | jq -r '.[0] .auth .tokens .access_token ')
ORGANIZATION_REGION=$(axway auth list --json | jq -r '.[0] .org .region')
echo "Done"

echo ""
echo "Preparing product plan unit if not available"
create_productplanunit_if_not_exist
echo "Done."


echo ""
if [[ $# == 0 ]]
then
	echo "Migrating all Unified Catalog items belonging to $CENTRAL_ENVIRONMENT environment into Asset and Product"
	migrate $PLATFORM_ORGID $PLATFORM_TOKEN
else
	echo "Migrating $1 Unified Catalog item into Asset and Product"
	migrate $PLATFORM_ORGID $PLATFORM_TOKEN "$1"
fi
 
echo "Done."

exit 0
