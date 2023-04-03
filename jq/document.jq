{
    group: "catalog",
    apiVersion: "v1",
    kind: "Document",
    title: env.docTitle,
    metadata: {
        scope: {
            kind: "Product",
            name: env.PRODUCT_NAME,
        }
    },
    spec: {
        sections: [
        {
            title: env.docTitle,
            articles: [
                .[] | {
                     kind: "Resource", 
                     name: .name,
                     title: .title
                }
            ]

        }
        ]
    }
}