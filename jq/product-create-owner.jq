{
    "group": "catalog",
    "apiVersion": "v1alpha1",
    "kind": "Product",
    "title": $product_title,
    "owner": {
        "type": "team",
        "id": $teamId,
    },
    "spec": {
        "assets": [
            {
                "name": $asset_name
            }
        ],
        "categories": [],
        "description": $description
    },
	"tags": [
		"Migrated from Unified Catalog"
	],
}