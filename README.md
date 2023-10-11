# Unified Catalog Migration

Tool for migrating your Unified Catalog items and assets to Marketplace products.

The script will:

1. Log into the platform using the `axway auth login` either using the browser or using a service account (if set in the configuration file)
2. Read all existing catalog items from a specific environment
3. For each catalog item
    * Find the linked API Service
    * Create an asset (or use an existing one) and linked it to the API Service
    * Create a product (if not existing yet) and linked it to the asset created
    * (Optional) Publish the product to the desire Marketplace
    * (Optional if product is published) Read existing Active subscription and create the corresponding Marketplace subscription / application if exists

## Pre requisites

* [Axway CLI](https://docs.axway.com/bundle/amplify-central/page/docs/integrate_with_central/cli_central/index.html)
* [jq](https://jqlang.github.io/jq/)
* [curl](https://curl.se/)

The script can be run on Microsfot Windows bash shell or on Linux

## Configuration

An environment file is available in config directory to setup some properties:

* _CLIENT_ID_ to use a service account instead of a real user
* _CLIENT_SECRET_ to set the service account private key.
* _CENTRAL_ENVIRONMENT_ to set the environment where to source the Catalog Items
* _PLAN_TITLE_ to set the default plan title
* _PLAN_QUOTA_ to set the default plan quota
* _PLAN_APPROVAL_MODE_ - automatic (default) or manual
* _PUBLISH_TO_MARKETPLACES_ to know if products need to be published to Marketplace
* _MARKETPLACE_TITLE_ to give the Marketplace title where the product needs to be published
* _ASSET_NAME_FOLLOW_SERVICE_VERSION_ to help naming the Asset based on the APIService name (see Note below)

Note regarding _ASSET_NAME_FOLLOW_SERVICE_VERSION_:
 When same service (same name) exists in multiple environments, we will create 1 Asset per major service release and only one Product
 For that you need to set _ASSET_NAME_FOLLOW_SERVICE_VERSION=Y_

Sample:

* Env1: APIService1 - v1.0.0
* Env2: APIService1 - v1.0.1
* Env3: APIService1 - v2.0.0

After Migration: using _ASSET_NAME_FOLLOW_SERVICE_VERSION=Y_

* Asset APIService1 V1 linked to APIService1 - v1.0.0 and APIService1 - v1.0.1
* Asset APIService1 V2 linked to APIService1 - v2.0.0
* Product APIService1 linked to Asset APIService1 V1 and Asset APIService1 V1

After Migration: using _ASSET_NAME_FOLLOW_SERVICE_VERSION=N_
* Asset APIService1 linked to APIService1 - v1.0.0 and APIService1 - v1.0.1 and APIService1 - v2.0.0
* Product APIService1 linked to Asset APIService1

## Mapping Unified Catalog => Marketplace

The following table shows how the properties from the Unified Catalog object are used to create the Marketplace objects:

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
|  Category(ies)                       |                      | Category(ies) |                          |                         |
|                                      |                      |               |                          |                         |
| **CatalogItemDocumentation**         |                      |               |                          |                         |
|  Value                               |                      | Article       |                          |                         |
|                                      |                      |               |                          |                         |
| **Subscription**                     |                      |               |                          |                         |
|  Name                                |                      |               | Name                     |                         |
|  Application name (if available)     |                      |               |                          | Name                    |
|  OwningTeam                          |                      |               | OwningTeam               | OwningTeam              |

### Subscription handling

Unified Catalog subscription and Marketplace are different.
For Unified Catalog there is one subscription per application per Catalog Item
From the Marketplace it will be translated to one subscription per plan and per application to guarantee that the provider can enforce the quota correct, that is defined in the product plan.

![Alt text](subscription.png)

Due to that, the migration script creates only 1 subscription for each individual resources available in the product. The subscription is reused to add the Access to the various application.

**Limitation**:
On Marketplace side, it is not possible to access the same product resource using a subscription plan having a quota restriction and multiple applications, to help provider to correctly enforce the subscription plan quotas.
The migration script displays this message `/!\ Cannot add access to {UNIFED_CATAOLOGSUBSCRIPTION_APPLICATION_NAME} using subscription {MARKETPLACE_SUBSCRIPTION_NAME} : access already exist for another application` if multiple applications try to access the same resource using the same subscription.

You can overcome this by using the unlimited quota variable: `PLAN_QUOTA="unlimited"`

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

* Tags from the Unified Catalog are not added to the product
* No product visibility is set based on the catalog item sharing
* Product can be published in only one Marketplace
