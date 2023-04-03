{
  group: "catalog",
  apiVersion: "v1alpha1",
  kind: "Quota",
  title: "Limited quota to x transactions",
  metadata: {
    scope: {
      kind: "ProductPlan",
      name: $product_plan_name
    }
  },
  spec: {
    unit: "transactions",
    pricing: {
      type: "fixed",
      "limit": {
                "type": "strict",
                "value": 1
            },
        "interval": "monthly"
      },
    resources: [
             {
                "kind": "AssetResource",
                "name": $resource_name
            }
    ]
  }
}
