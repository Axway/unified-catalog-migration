# migrateUnifiedCatalog

Tool for migrating Unified Catalog service into Marketplace product

The script is:

1. login using the `axway auth login`
2. reading all existing catalog items
3. For each catalog item
    * create an asset
    * create a product
    * publish the product
    * read existing Active subscription and create the corresponding MP subscription

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
* PUBLISH_TO_MARKETPLACES to know if products need to be publish to marketplace
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

## Improvements

* Categories
* Tags
* add the product visibility based on the catalog item sharing
* Publish product to all available Marketplaces
