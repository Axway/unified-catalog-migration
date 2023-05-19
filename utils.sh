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

##########################################################
# Getting data from the marketplace                      #
# either return the entire object or the portion         #
# specified with $2 as a jq extract expression           #
#                                                        #
# $1 (mandatory): url to call                            #
# $2 (optional): jq expression to extract information    #
##########################################################
function getFromMarketplace() {

	urlPath=$1
	URL=$MARKETPLACE_URL$urlPath
	#echo "url for MP = "$URL

	curl -s -k -L ${URL} -H "Content-Type: application/json" -H "X-Axway-Tenant-Id: $PLATFORM_ORGID" --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/getFromMarketplaceResult.json

	if [[ $2 == "" ]]
	then
		echo `cat $TEMP_DIR/getFromMarketplaceResult.json`
	else
		echo `cat $TEMP_DIR/getFromMarketplaceResult.json | jq -r "$2"`
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

	URL=$MARKETPLACE_URL$1
	#echo "url for MP = "$URL
	#echo "curl -s -k -L ${URL} -H "Content-Type: application/json" --header 'Authorization: Bearer '$PLATFORM_TOKEN -d cat $2"
	curl -s -k -L ${URL} -H "Content-Type: application/json" -H "X-Axway-Tenant-Id: $PLATFORM_ORGID" --header 'Authorization: Bearer '$PLATFORM_TOKEN -d "`cat $2`" > $outputFile

	cat $outputFile
}

############################################
# Getting the Unified Catalog Documentation
# Always read the 1st revision
# $1: CATALOG_ID
############################################
function readCatalogDocumentationFromItsId() {

	# variable assignment
	CATALOG_ID=$1

	# Get catalog documentation property
	URL=$CENTRAL_URL'/api/unifiedCatalog/v1/catalogItems/'$CATALOG_ID'/revisions/1/properties/documentation'
	curl -s --location --request GET ${URL} --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/catalogItemDocumentation.txt
	
	# remove 1st and last " from the string
	cat $TEMP_DIR/catalogItemDocumentation.txt | cut -d "\"" -f 2 > $TEMP_DIR/catalogItemDocumentationAfterCut.txt
	DOC_TEMP=`cat $TEMP_DIR/catalogItemDocumentationAfterCut.txt`

	# replace \n with newline
	sed 's/\\n/\'$'\n''/g' <<< $DOC_TEMP > $TEMP_DIR/catalogItemDocumentationCleaned.txt
	cat $TEMP_DIR/catalogItemDocumentationCleaned.txt
}
