{
    "group": "catalog",
    "apiVersion": "v1alpha1",
    "kind": "Product",
    "title": $product_title,
    "spec": {
        "assets": [
            {
                "name": $asset_name
            }
        ],
        "categories": [],
        "autoRelease": {
            "releaseType": "patch"
        },
        "description": $description
    },
	"tags": [
		"Migrated from Unified Catalog"
	],
    "icon": "data:image/png;base64,__iconBase64__",
}