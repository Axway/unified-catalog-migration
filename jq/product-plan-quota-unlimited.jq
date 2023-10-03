{
  group: "catalog",
  apiVersion: "v1alpha1",
  kind: "Quota",
  title: "Unlimited quota",
  metadata: {
    scope: {
      kind: "ProductPlan",
      name: $product_plan_name
    }
  },
  spec: {
    unit: $unit,
    pricing: {
      type: "unlimited"
      },
    resources: [
             {
                "kind": "AssetResource",
                "name": $resource_name
            }
    ]
  }
}
