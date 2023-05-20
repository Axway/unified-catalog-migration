{
    group: "catalog",
    apiVersion: "v1alpha1",
    kind: "PublishedProduct",
    "owner": {
        "type": "team",
        "id": $teamId,
    },
    metadata: {
        scope: {
            kind: "Marketplace",
            name: $marketplace_name,
        }
    },
    spec: {
        product: {
            name: $product_name
        }
    }
}