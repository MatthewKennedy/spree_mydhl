# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`spree_mydhl` is a Spree Commerce extension (Rails engine gem) that adds DHL Express as a shipping rate calculator. It integrates with the DHL Express MyDHL API to fetch real-time shipping rates during checkout.

## Commands

### Setup (first time or after dependency changes)
```bash
bundle update
bundle exec rake test_app   # generates spec/dummy Rails app
```

### Running Tests
```bash
bundle exec rspec                                        # all specs
bundle exec rspec spec/lib/spree_mydhl/dhl_express_client_spec.rb  # single file
bundle exec rspec spec/models/spree/calculator/shipping/dhl_express_spec.rb
```

### Linting
```bash
bundle exec rubocop
bundle exec rubocop --autocorrect
```

### Releasing
```bash
bundle exec gem bump -p -t   # bump patch version and tag
bundle exec gem release
```

## Architecture

### Core Components

**`SpreeMydhl::DhlExpressClient`** (`lib/spree_mydhl/dhl_express_client.rb`)
- Plain Ruby HTTP client wrapping the DHL Express MyDHL API (`/rates` endpoint)
- Authenticates with HTTP Basic Auth (`api_key`:`api_secret`); 5s open timeout, 10s read timeout
- Supports sandbox (`https://express.api.dhl.com/mydhlapi/test`) and production (`https://express.api.dhl.com/mydhlapi`) URLs
- Primary public method: `#cheapest_rate` — returns the minimum `BILLC` (billed currency) price across all returned products, or `nil` on any error
- Optionally filters by a specific `product_code`; can set `customs_declarable` explicitly or auto-detect from country mismatch
- Rounds weight to 3 decimal places; length/width/height to 2 decimal places
- All errors are rescued and logged; never raises to the caller

**`Spree::Calculator::Shipping::DhlExpress`** (`app/models/spree/calculator/shipping/dhl_express.rb`)
- Spree `ShippingCalculator` subclass; implements `#compute_package` and `#available?`
- Configured via Spree preferences (stored per shipping method in admin):
  - `api_key` — MyDHL API Key (required)
  - `api_secret` — MyDHL API Secret (required)
  - `account_number` — DHL account number (required)
  - `stock_location_id` — integer; ties the calculator to a specific origin stock location (required)
  - `unit_of_measurement` — `metric` or `imperial` (default: `metric`)
  - `currency` — overrides order/store default currency
  - `sandbox` — boolean, default `false`
  - `product_code` — optional DHL service level filter (e.g. `P` for Express Worldwide)
  - `customs_declarable` — optional boolean override for customs declaration
  - `minimum_weight` — optional lower weight bound for availability
  - `maximum_weight` — optional upper weight bound for availability
  - `markup_percentage` — optional decimal; applied as a percentage on top of the DHL rate (e.g. `10` = +10%)
  - `handling_fee` — optional flat fee added after any percentage markup
  - `cache_ttl_minutes` — integer, default `10`; controls how long rates are cached in `Rails.cache`
- `#available?` returns false if required preferences are blank, stock location doesn't match, weight is outside bounds, or destination address/country is missing
- `#compute_package` fetches a live rate via `DhlExpressClient`, caches it for `cache_ttl_minutes` minutes, then applies markup/handling via `#apply_markup`; cache key includes origin/destination/dimensions/customs_declarable/date (cache also expires naturally at midnight)
- Dimension extraction from variants: max length, max width, and summed height×quantity; falls back to 1.0 if all variants report zero. Weight falls back to 0.1 if zero.
- Currency resolved in order: preference → order currency → store default currency

**`Spree::Admin::BaseHelperDecorator`** (`app/helpers/spree/admin/base_helper_decorator.rb`)
- Extends Spree admin preference rendering for three calculator fields:
  - `unit_of_measurement`: dropdown (Metric | Imperial)
  - `product_code`: dropdown of all supported DHL product codes
  - `stock_location_id`: dropdown of active stock locations

### DHL Product Codes

| Code | Service |
|------|---------|
| `P` | Express Worldwide |
| `D` | Express Worldwide Doc |
| `K` | Express 9:00 |
| `W` | Express 10:30 |
| `T` | Express 12:00 |
| `Y` | Express 12:00 Doc |
| `H` | Economy Select |
| `N` | Domestic Express |

### Registration

The calculator is registered in `config/initializers/spree.rb`:
```ruby
Rails.application.config.after_initialize do
  Spree.calculators.shipping_methods << Spree::Calculator::Shipping::DhlExpress
end
```

This makes it available in the Spree admin when configuring shipping methods.

### Extension Conventions

- Follows standard Spree extension structure (`spree_extension` gem, Zeitwerk autoloading)
- Decorator pattern: any `*_decorator*.rb` files in `app/` are auto-loaded by the engine
- `SpreeMydhl::Config` is a `Spree::Preferences::Configuration` instance initialized at boot
- `SpreeMydhl.queue` defaults to `Spree.queues.default` for any background jobs

### Testing Setup

- Specs require a generated dummy app (`spec/dummy/`); run `rake test_app` to generate it
- `spec/spec_helper.rb` loads dotenv, the dummy app environment, and `spree_dev_tools` RSpec helpers
- HTTP calls are stubbed with WebMock in `dhl_express_client_spec.rb`
- Use `instance_double` for Spree objects (`Spree::Stock::Package`, etc.) to avoid loading the full stack
- Additional specs: `spec/i18n_spec.rb` (validates i18n keys) and `spec/zeitwerk_spec.rb` (validates eager loading)

### RuboCop Configuration

- Target Ruby 3.3, `rubocop-rails` plugin enabled
- Line length max: 150
- `Style/Documentation` and `Style/FrozenStringLiteralComment` are disabled
- `spec/dummy/` and `lib/generators/` are excluded from linting
- `spec/.rubocop.yml` adds `rubocop-rspec` and disables `Metrics/BlockLength` and `Style/BlockDelimiters` for specs

### CI

CircleCI runs tests against both PostgreSQL and MySQL in parallel, plus a Brakeman security scan. See `.circleci/config.yml`.
