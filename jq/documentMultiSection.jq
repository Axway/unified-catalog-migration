{
    group: "catalog",
    apiVersion: "v1",
    kind: "Document",
    title: env.docResource,
    metadata: {
        scope: {
            kind: "Product",
            name: env.PRODUCT_NAME,
        }
    },
    spec: {
        sections: [
           {
                title: env.sectionTitle1,
                articles: [
                    {
                         kind: "Resource", 
                         name: env.nameVueEnsemble,
                         title: "Vue d'ensemble"
                    }
                ],
            },
            {    
                title: env.sectionTitle2,
                articles: [
                    {
                         kind: "Resource", 
                         name: env.nameCasUsage,
                         title: "Cas d'usage"
                    }
                ],
            },
            {    
                title: env.sectionTitle3,
                articles: [
                    {
                         kind: "Resource", 
                         name: env.nameHistoriqueVersions,
                         title: "Historique des versions"
                    }
                ],
            },
            {
                title: env.sectionTitle4,
                articles: [
                    {
                         kind: "Resource", 
                         name: env.nameCasMetiers,
                         title: "Cas métiers"
                    }
                ],
            }                
        ]
    }
}