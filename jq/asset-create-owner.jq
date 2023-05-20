{
	"group": "catalog",
	"apiVersion": "v1alpha1",
	"kind": "Asset",
	"title": $title,
    "owner": {
        "type": "team",
        "id": $teamId,
    },
	"attributes": {},
	"tags": [
		"Migrated from Unified Catalog"
	],
	"spec": {
		"type": "API",
		"autoRelease": {
			"releaseType": "patch"
		},
		"categories": [],
		"description": $description
	},
	"access": {
        "approval": "automatic"
    },
    "icon": $icon,
	"state": "draft"
}