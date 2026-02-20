# Spree MyDHL

A [Spree Commerce](https://spreecommerce.org) extension that adds MyDHL as a real-time shipping rate calculator. It connects to the [DHL MyDHL API](https://developer.dhl.com/api-reference/dhl-express-mydhl-api) during checkout to fetch live rates for your configured shipping methods.

## Features

- Real-time rates from the MyDHL API
- Filters available shipping methods by Spree stock location
- Optional product code filter (e.g. lock a shipping method to *Express Worldwide* only)
- Automatic international/domestic detection for customs declarations
- Optional weight-based availability rules (min/max)
- Configurable rate caching to avoid redundant API calls
- Sandbox and production API support
- Admin dropdown selectors for stock location and DHL product code

## Requirements

- Ruby >= 3.2
- Spree >= 5.3.3

## Installation

1. Add the gem to your Gemfile:

```ruby
bundle add spree_mydhl
```

2. Run the install generator:

```bash
bundle exec rails g spree_mydhl:install
```

3. Restart your server.

## Configuration

### DHL API Credentials

Sign in to the [DHL Developer Portal](https://developer.dhl.com) and create an application to obtain your API Key and API Secret.

### Setting Up a Shipping Method

1. In the Spree admin, go to **Configuration → Shipping Methods** and create a new shipping method.
2. Select **DHL Express** as the calculator.
3. Fill in the calculator preferences:

| Preference | Description |
|---|---|
| **API Key** | Your DHL MyDHL API key |
| **API Secret** | Your DHL MyDHL API secret |
| **Account Number** | Your DHL account number |
| **Stock Location** | The stock location shipments originate from |
| **Unit of Measurement** | `metric` (kg/cm) or `imperial` (lb/in) — must match your variant dimensions |
| **Currency** | Currency for quoted rates (defaults to the store's default currency) |
| **Sandbox** | Enable to use the DHL test environment |
| **Product Code** | Optional — restrict to a specific DHL service (see below) |
| **Customs Declarable** | Optional — override automatic international detection |
| **Minimum Weight** | Optional — hide this method below a package weight threshold |
| **Maximum Weight** | Optional — hide this method above a package weight threshold |
| **Markup Percentage** | Optional — percentage added on top of the DHL rate (e.g. `10` adds 10%) |
| **Handling Fee** | Optional — flat amount added after any percentage markup |
| **Cache TTL Minutes** | How long to cache rates (default: `10`) |

### DHL Product Codes

By default the calculator returns the cheapest rate across all DHL products available for the route. Set a product code to lock the shipping method to a specific service level:

| Code | Service |
|---|---|
| `P` | Express Worldwide |
| `D` | Express Worldwide Doc |
| `K` | Express 9:00 |
| `W` | Express 10:30 |
| `T` | Express 12:00 |
| `Y` | Express 12:00 Doc |
| `H` | Economy Select |
| `N` | Domestic Express |

### Variant Dimensions

The API requires package dimensions. These are derived from your Spree variant attributes:

- **Length** — largest `depth` across all items in the package
- **Width** — largest `width` across all items in the package
- **Height** — sum of `height × quantity` across all items

Dimensions fall back to `1.0` if all variants report zero. Make sure your variant dimensions are stored in units consistent with the **Unit of Measurement** preference — no automatic conversion is applied.

### Customs Declarations

By default, `isCustomsDeclarable` is set to `true` whenever the origin and destination country codes differ. Use the **Customs Declarable** preference to override this (e.g. for shipments between territories that share a country code).

## Upgrading

### From a version using `username` / `password` preferences

Version 0.1.0 renamed the credential preferences from `username`/`password` to `api_key`/`api_secret`. Run the bundled migration to update any existing shipping method configurations:

```bash
bundle exec rails db:migrate
```

## Development

```bash
bundle update
bundle exec rake test_app
bundle exec rspec
bundle exec rubocop
```

## Releasing

```bash
bundle exec gem bump -p -t
bundle exec gem release
```

## License

[AGPL-3.0-or-later](LICENSE.md)
