{
    group: "catalog",
    apiVersion: "v1alpha1",
    kind: "ReleaseTag",
    metadata: {
        scope: {
            kind: "Product",
            name: $productName,
        }
    },
    spec: {
        releaseType: "major"
    }
}