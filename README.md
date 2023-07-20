# migrateUnifiedCatalog

Tool for migrating Unified Catalog service into Marketplace product

The script will:

1. log into the plaftorm using the `axway auth login` either using the browser or using a service account (if set in the configuration file)
2. read all existing catalog items from a specific environment
3. For each catalog item
    * find the linked API Service
    * create an asset and linked it to the API Service
    * create a product and linked it to the asset created
    * (optional) publish the product to the desire Marketplace
    * (optional if product is published) read existing Active subscription and create the corresponding Marketplace subscription / Application if exist

## Pre requisites

* Axway CLI
* jq
* curl

The script can be run under windows bash shell or Linux

## Configuration

An environment file is available in config directory to setup some properties:

* CLIENT_ID to use a service account instead of a real user
* CLIENT_SECRET to set the service account private key.
* CENTRAL_ENVIRONMENT to set the environment where to source the Catalog Items
* PLAN_TITLE to set the default plan title
* PLAN_QUOTA to set the default plan quota
* PLAN_APPROVAL_MODE - automatic (default) or manual
* PUBLISH_TO_MARKETPLACES to know if products need to be publish to Marketplace
* MARKETPLACE_TITLE to give the Marketplace title where the product needs to be published.

## Mapping Unified Catalog => Marketplace

The following table show how the properties from the Unified Catalog object are used to create the Marketplace objects:

| Initial Objects                      | Asset                | Product       | Marketplace subscription | Marketplace application |
|------------------------------------|------------------------|---------------|--------------------------|-------------------------|
| **Consumer instance**                |                      |               |                          |                         |
|  Id                                  |                      |               |                          |                         |
|  Name                                |                      |               |                          |                         |
|  Title                               | Title                | Title         |                          |                         |
|  Description                         | Description          | Description   |                          |                         |
|  API Service                         | APIService           |               |                          |                         |
|                                      |                      |               |                          |                         |
| **APIService**                       |                      |               |                          |                         |
|  Icon (not used)                     |                      |               |                          |                         |
|                                      |                      |               |                          |                         |
| **APIServiceInstance**               |                      |               |                          |                         |
|  CredentialRequestDefinition         |                      |               |                          |                         |
|  AccessRequestDefinition             |                      |               |                          |                         |
|                                      |                      |               |                          |                         |
| **CatalogItem (= consumerInstance)** |                      |               |                          |                         |
|  Image/base64                        | Icon                 | Icon          |                          |                         |
|                                      |                      |               |                          |                         |
| **CatalogItemDocumentation**         |                      |               |                          |                         |
|  Value                               |                      | Article       |                          |                         |
|                                      |                      |               |                          |                         |
| **Subscription**                     |                      |               |                          |                         |
|  Name                                |                      |               | Name                     |                         |
|  Application name (if available)     |                      |               |                          | Name                    |
|  OwningTeam                          |                      |               | OwningTeam               | OwningTeam              |

## Usage

Migrating all catalog item link to an environment:

```bash
./migrateUnifiedCatalog.sh
```

Migrating a single catalog item link to an environment:

```bash
./migrateUnifiedCatalog.sh "catalogItemTitle"
```

## Known limitations

* Categories from Unified Catalog are not added as a Product Category
* Tags from the Unified Catalog are not added to the product
* No product visibility set based on the catalog item sharing
* Product can be publish in only one Marketplace
