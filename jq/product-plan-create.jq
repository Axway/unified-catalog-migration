{
  group: "catalog",
  apiVersion: "v1alpha1",
  kind: "ProductPlan",
  title: $plan_title,
  spec: {
    product: $product,
    description: "Free access to the api",
    type: "free",
    subscription: {
      interval: {
        type: "months",
        length: 1
      },
      renewal: "automatic",
      approval: $approvalMode
    }
  },
  state: "draft"
}