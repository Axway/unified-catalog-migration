# migrateUnifiedCatalog

Tool for migrating Unified Catalog service into Marketplace product

The script is:

1. login using the `axway auth login`
2. reading all existing catalog items
3. For each catalog item
    * create an asset
    * create a product
    * publish the product

## Pre requisites

Axway CLI
jq
curl

The script can be run under windows bash shell or Linux

## Configuration

An environment file is available in config directory to setup some properties:

* CLIENT_ID to use a service account instead of a real user
* CLIENT_SECRET to set the service account private key.
* CENTRAL_URL (default US) to connect to the appropriate environment
* PLAN_TITLE to set the default plan title
* PLAN_QUOTA to set the default plan quota
* PUBLISH_TO_MARKETPLACES to know if products need to be publish to marketplace

## Usage

```bash
./migrateUnifiedCatalog.sh
```

## Improvements

* Categories
* add owner of Asset / Product & Plan based on the service owner.
* add the sharing of catalog?
