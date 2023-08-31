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
# 3- Stage name
# 4- catalog item name to migrate (optional)
####################################################
function migrate() {

	mkdir $TEMP_DIR

	# map parameters
	PLATFORM_ORGID=$1
	PLATFORM_TOKEN=$2
	STAGE_NAME=$3
	INPUT_TITLE=$4

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
	cat $TEMP_DIR/$TEMP_FILE | jq -rc ".[] | {id: .metadata.id, name: .name, title: .title, apiserviceName: .references.apiService, apiserviceRevision: .references.apiServiceRevision, tags: .tags, environment: .metadata.scope.name, ownerId: .owner.id}" | while IFS= read -r line ; do

		CONSUMER_INSTANCE_ID=$(echo $line | jq -r '.id')
		CONSUMER_INSTANCE_NAME=$(echo $line | jq -r '.name')
		CONSUMER_INSTANCE_TITLE=$(echo $line | jq -r '.title')
		CONSUMER_INSTANCE_OWNER_ID=$(echo $line | jq -r '.ownerId')
		CATALOG_APISERVICE=$(echo $line | jq -r '.apiserviceName')
		CATALOG_APISERVICE_REVISION=$(echo $line | jq -r '.apiserviceRevision')
		CATALOG_APISERVICEENV=$(echo $line | jq -r '.environment')
		CATALOG_TAGS=$(echo $line | jq -r '.tags')

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
			#filter the one that match latestersion to the consumerInstance-references.apiServiceRevision
			CATALOG_ID=`jq --arg FILTER_VALUE "$CATALOG_APISERVICE_REVISION" -r '.[] | select(.latestVersion==$FILTER_VALUE)' $TEMP_DIR/catalogItem.json | jq -r ". | .id"`
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

			done <<< `cat $TEMP_DIR/catalogItemCategoryId.txt`
			echo "			categories found = $CATALOG_CATEGORIES"
		else
			echo "			no categories found!"
		fi

		echo "	Checking if asset $CONSUMER_INSTANCE_TITLE already created..."
		axway central get assets -q "title=='$CONSUMER_INSTANCE_TITLE';metadata.references.name=="$CATALOG_APISERVICEENV";metadata.references.kind==environment" -o json > $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME-exist.json
		# file will never be empty but only contain [] if nothing found.
		if [ `jq length $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME-exist.json` != 0 ]; then
			# The file is empty.
			echo "		Assets exists, nothing to do"
			# keep information
			export ASSET_NAME=$(jq -r .[0].name $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME-exist.json)
		else
			# Process.
			echo "		Asset does not exist, we can create it"

			# creating asset in Central
			echo "	creating asset file..."
			if [[ $CONSUMER_INSTANCE_OWNER_ID == null ]]
			then
				echo "		without owner"
				jq -n -f ./jq/asset-create.jq --arg title "$CONSUMER_INSTANCE_TITLE" --arg description "$CATALOG_DESCRIPTION" > $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME.json
				error_exit "Error while creating asset file $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME.json"
			else
				echo "		with owningTeam : $CONSUMER_INSTANCE_OWNER_ID"
				jq -n -f ./jq/asset-create-owner.jq --arg title "$CONSUMER_INSTANCE_TITLE" --arg description "$CATALOG_DESCRIPTION" --arg teamId "$CONSUMER_INSTANCE_OWNER_ID"> $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME.json
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
			jq -n -f ./jq/asset-mapping.jq --arg asset_name "$ASSET_NAME" --arg stage_name "$STAGE_NAME" --arg env_name "$CATALOG_APISERVICEENV" --arg srv_name "$CATALOG_APISERVICE" > $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME-mapping.json
			echo "	Posting asset mapping to Central"
			axway central create -f $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME-mapping.json -y -o json > $TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME-mapping-created.json
			error_exit "Problem creating asset mapping" "$TEMP_DIR/asset-$CONSUMER_INSTANCE_NAME-mapping-created.json"
		fi # asset exist?

		# Do the same for product but not for subscription... It could help to solve Mercadona duplicate issues: https://jira.axway.com/browse/APIGOV-25743
		echo "	Checking if product $CONSUMER_INSTANCE_TITLE already created..."
		axway central get products -q "title=='$CONSUMER_INSTANCE_TITLE';metadata.references.name=="$ASSET_NAME";metadata.references.kind==Asset" -o json > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-exist.json
		# file will never be empty but only contain [] if nothing found.
		if [ `jq length $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-exist.json` != 0 ]
		then
			# The file is empty.
			echo "		Product exists, nothing to do"
			# keep information
			export PRODUCT_NAME=`jq -r .[0].name $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-exist.json`
		else
			# Process.
			echo "		Product does not exist, we can create it"

			# reading asset resource name (used for quota creation)
			echo "	Reading the created asset resource name..."
			export RESOURCE_NAME=`axway central get assetresource -s $ASSET_NAME -o json | jq -r .[].name`

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
			if [[ $CONSUMER_INSTANCE_OWNER_ID == null ]]
			then
				echo "		without owner"
				jq -n -f ./jq/product-plan-create.jq --arg plan_name free-$PRODUCT_NAME --arg plan_title "$PLAN_TITLE" --arg product $PRODUCT_NAME --arg approvalMode $PLAN_APPROVAL_MODE > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-plan.json
			else
				echo "		with owningTeam : $CONSUMER_INSTANCE_OWNER_ID"
				jq -n -f ./jq/product-plan-create-owner.jq --arg plan_name free-$PRODUCT_NAME --arg plan_title "$PLAN_TITLE" --arg product $PRODUCT_NAME --arg approvalMode $PLAN_APPROVAL_MODE  --arg teamId "$CONSUMER_INSTANCE_OWNER_ID" > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-plan.json
			fi
			axway central create -f $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-plan.json -o json -y > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-plan-created.json
			error_exit "Problem when creating a Product plan" "$TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-plan-created.json"

			# retrieve product plan since there could be naming conflict
			export PRODUCT_PLAN_NAME=`jq -r .[0].name $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-plan-created.json`
			export PRODUCT_PLAN_ID=`jq -r .[0].metadata.id $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-plan-created.json`

			# Adding plan quota
			echo "		Adding plan quota..."
			jq -n -f ./jq/product-plan-quota.jq --arg product_plan_name $PRODUCT_PLAN_NAME --arg resource_name $ASSET_NAME/$RESOURCE_NAME > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-plan-quota.json
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

		fi # product exist?

		# do we need to publish to the marketpalces?
		if [[ $PUBLISH_TO_MARKETPLACES == "Y" ]]
		then

			# read Marketplace URL
			MP_URL=$(readMarketplaceUrlFromMarketplaceName)
			MP_GUID=$(readMarketplaceGuidFromMarketplaceName)

			echo "	Checking that $CONSUMER_INSTANCE_TITLE is not already published to $MARKETPLACE_TITLE..."
			# check the product is not already published for this Marketplace
			axway central get publishedproduct -s $MP_GUID -q "metadata.references.name=="$PRODUCT_NAME";metadata.references.kind==product" -o json > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-published.json

			if [ `jq length $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-published.json` == 0 ]
			then
				# TODO - Manage publication to all Marketplaces?
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
			#TODO - ask whether or not to create subscription?

			##########
			# WARNING: Consumerinstance != Catalog item - only the name/title can link both
			##########

			# read catalog id from catalog name
			echo "	Reading associated Unified Catalog subscription(s)...."
			curl -s --location --request GET $CENTRAL_URL'/api/unifiedCatalog/v1/catalogItems/'$CATALOG_ID'/subscriptions?query=%28state==ACTIVE%29' --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/catalogItemSubscriptions.json
			echo "	Found " `cat $TEMP_DIR/catalogItemSubscriptions.json | jq '.|length'` " ACTIVE subscription(s)"

			# loop on subscription
			cat $TEMP_DIR/catalogItemSubscriptions.json | jq -rc ".[] | {subId: .id, subName: .name, teamId: .owningTeamId, appName: .properties[0].value.appName}" | while IFS= read -r line ; do
				# read subscriptionId, application name, teamId and subscription name
				SUBSCRIPTION_ID=$(echo $line | jq -r '.subId')
				SUBSCRIPTION_NAME=$(echo $line | jq -r '.subName')
				SUBSCRIPTION_OWNING_TEAM=$(echo $line | jq -r '.teamId')
				SUBSCRIPTION_APP_NAME=$(echo $line | jq -r '.appName')

				echo "		Need to migrate subscription ($SUBSCRIPTION_NAME) for team ($SUBSCRIPTION_OWNING_TEAM) using application ($SUBSCRIPTION_APP_NAME) to marketplace ($MARKETPLACE_TITLE)"

				echo "			Searching product id in marketplace..."
				SANITIZE_CATALOG_NAME=${CONSUMER_INSTANCE_TITLE// /%20}
				CONTENT=$(getFromMarketplace "$MP_URL/api/v1/products?limit=10&offset=0&search=$SANITIZE_CATALOG_NAME&sort=-lastVersion.metadata.createdAt%2C%2Bname")
				MP_PRODUCT_ID=`echo $CONTENT | jq -r ".items[0].id"`
				MP_PRODUCT_VERSION_ID=`echo $CONTENT | jq -r ".items[0].latestVersion.id"`
				echo "			Found product id in marketplace:" $MP_PRODUCT_ID
				echo "			Found product latest version id in marketplace:" $MP_PRODUCT_VERSION_ID
				echo "			Searching product plan id in marketplace..."
				MP_PRODUCT_PLAN_ID=$(getFromMarketplace "$MP_URL/api/v1/products/$MP_PRODUCT_ID/plans" ".items[0].id")
				echo "			Found product plan id in marketplace:" $MP_PRODUCT_PLAN_ID
				MP_ASSETRESOURCE_ID=$(getFromMarketplace "$MP_URL/api/v1/products/$MP_PRODUCT_ID/versions/$MP_PRODUCT_VERSION_ID/assetresources" ".items[0].id")
				echo "			Found product asset resource id in marketplace:" $MP_ASSETRESOURCE_ID

				echo "			Checking if subscription already exist"
				# it is forbidden for the same team to have 2 subsctiptions on the same plam
				CONTENT=$(getFromMarketplace "$MP_URL/api/v1/subscriptions?product.id=$MP_PRODUCT_ID&owner.id=$SUBSCRIPTION_OWNING_TEAM")
				NB_SUBSCRIPTION=`echo $CONTENT | jq '.items|length'`

				if [[ $NB_SUBSCRIPTION != 0 ]]
				then
					echo "				A subscription already exist for team $SUBSCRIPTION_OWNING_TEAM... No need to create."
				else
					echo "			Create subscription $SUBSCRIPTION_NAME...."
					#SUBNAME=$PRODUCT_NAME-$SUBSCRIPTION_OWNING_TEAM
					jq -n -f ./jq/product-mp-subscription.jq --arg subscriptionTitle "$SUBSCRIPTION_NAME" --arg teamId $SUBSCRIPTION_OWNING_TEAM --arg planId $MP_PRODUCT_PLAN_ID --arg productId $MP_PRODUCT_ID > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-subscription-$SUBSCRIPTION_ID.json
					CONTENT=$(postToMarketplace "$MP_URL/api/v1/subscriptions" $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-subscription-$SUBSCRIPTION_ID.json $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-subscription-$SUBSCRIPTION_ID-created.json)
					error_post "Problem creating subscription on Marketplace." $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-subscription-$SUBSCRIPTION_ID-created.json
					# read the subscriptionId from the created susbcription
					MP_SUBSCRIPTION_ID=`echo $CONTENT | jq -r ".id"`

					if [[ $SUBSCRIPTION_APP_NAME == null ]]
					then
						echo "			/!\ no application found, cannot create ManagedApplication / AccessRequest"
					else

						# check if managedapp not already exists to avoid duplicating it
						MP_MANAGED_APP_ID=$(getFromMarketplace "$MP_URL/api/v1/applications?limit=10&offset=0&search=$SUBSCRIPTION_APP_NAME&sort=-metadata.modifiedAt%2C%2Bname" ".items[0].id")

						if [[ MP_MANAGED_APP_ID == null ]]
						then
							# application does not exist yet... so we can create it
							echo "			Create managed application $SUBSCRIPTION_APP_NAME...."
							jq -n -f ./jq/product-mp-application.jq --arg applicationTitle $SUBSCRIPTION_APP_NAME --arg teamId $SUBSCRIPTION_OWNING_TEAM > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-application.json
							CONTENT=$(postToMarketplace "/api/v1/applications" $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-application.json $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-application-created.json)
							error_post "Problem creating application on Marketplace." $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-application-created.json
							MP_MANAGED_APP_ID=`echo $CONTENT | jq -r ".id"`
						else
							echo "			$SUBSCRIPTION_APP_NAME managedApp is already existing."
						fi

						# Now we need to check that we have all elements to create the access request ie CRD/ARD otherwise it will fails
						# read apisr and check ARD/CRD presence
						axway central get apisi -q "metadata.references.name==$CATALOG_APISERVICE&sort=metadata.audit.createTimestamp%2CDESC" -s $CATALOG_APISERVICEENV -o json > $TEMP_DIR/apis-$CATALOG_APISERVICEENV-$CATALOG_APISERVICE-instance.json
						# retrieve ARD / CRD....
						cat $TEMP_DIR/apis-$CATALOG_APISERVICEENV-$CATALOG_APISERVICE-instance.json | jq -rc ".[0] | {ard: .spec.accessRequestDefinition, crd: .spec.credentialRequestDefinitions}" > $TEMP_DIR/apis-$CATALOG_APISERVICEENV-$CATALOG_APISERVICE-instance-check.json
						ARD=`cat $TEMP_DIR/apis-$CATALOG_APISERVICEENV-$CATALOG_APISERVICE-instance-check.json | jq -rc ".ard"`
						CRD=`cat $TEMP_DIR/apis-$CATALOG_APISERVICEENV-$CATALOG_APISERVICE-instance-check.json | jq -rc ".crd"`
			
						if [[ $ARD != null && $CRD != null ]]
						then
							echo "			Create request access...."
							ACCESS_REQUEST_NAME="Something temporary"

							jq -n -f ./jq/product-mp-accessrequest.jq --arg accessRequestTile "$ACCESS_REQUEST_NAME" --arg productId "$MP_PRODUCT_ID" --arg productIdVersion "$MP_PRODUCT_VERSION_ID" --arg assetResourceId "$MP_ASSETRESOURCE_ID" --arg subscriptionId $MP_SUBSCRIPTION_ID > $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-application-access.json
							CONTENT=$(postToMarketplace "/api/v1/applications/$MP_MANAGED_APP_ID/accessrequests" $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-application-access.json $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-application-access-created.json)
							error_post "Problem creating application access on Marketplace." $TEMP_DIR/product-$CONSUMER_INSTANCE_NAME-application-access-created.json
						else
							echo "			/!\ Cannot proceed with AccessRequest as the service does not have the CredentialRequestDefinition nor the AccessRequestDefinition"
						fi
			
					fi

				fi

			done # loop over subscription

		fi # Publish to Marketplace
		
		# clean up current loop if no error happened...
		echo "	cleaning temp files..."
		if [[ $error == 0 ]] # does not work all the time as we set the error inside a loop /!\
		then
			rm $TEMP_DIR/*$CONSUMER_INSTANCE_NAME*
		fi

	done # loop over catalog items

	# clean up catalog item files
	if [[ $error == 0 ]]
	then
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
echo "Preparing a stage if not available"
create_stage_if_not_exist
echo "Done."

echo ""
if [[ $# == 0 ]]
then
	echo "Migrating all Unified Catalog items belonging to $CENTRAL_ENVIRONMENT environment into Asset and Product"
	migrate $PLATFORM_ORGID $PLATFORM_TOKEN $STAGE_NAME
else
	echo "Migrating $1 Unified Catalog item into Asset and Product"
	migrate $PLATFORM_ORGID $PLATFORM_TOKEN $STAGE_NAME "$1"
fi
 
echo "Done."

exit 0