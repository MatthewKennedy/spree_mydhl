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
- Authenticates with HTTP Basic Auth; supports sandbox and production URLs
- Primary public method: `#cheapest_rate` — returns the minimum `BILLC` (billed currency) price across all returned products, or `nil` on any error
- All errors are rescued and logged; never raises to the caller

**`Spree::Calculator::Shipping::DhlExpress`** (`app/models/spree/calculator/shipping/dhl_express.rb`)
- Spree `ShippingCalculator` subclass; implements `#compute_package` and `#available?`
- Configured via Spree preferences (stored per shipping method in admin): `username`, `password`, `account_number`, `origin_country_code`, `origin_postal_code`, `origin_city_name`, `unit_of_measurement`, `currency`, `sandbox`
- Caches API results in `Rails.cache` for 10 minutes; cache key includes origin/destination/dimensions/date
- Returns `nil` if preferences are incomplete, ship address is missing, or the API call fails
- Dimensions are summed across all package contents; falls back to 1.0 if all variants report zero

### Registration

The calculator is registered in `config/initializers/spree.rb`:
```ruby
Spree.calculators.shipping_methods << Spree::Calculator::Shipping::DhlExpress
```

This makes it available in the Spree admin when configuring shipping methods.

### Extension Conventions

- Follows standard Spree extension structure (`spree_extension` gem, Zeitwerk autoloading)
- Decorator pattern: any `*_decorator*.rb` files in `app/` are auto-loaded by the engine
- Background jobs inherit from `SpreeMydhl::BaseJob < Spree::BaseJob`, queued via `SpreeMydhl.queue`
- `SpreeMydhl::Config` is a `Spree::Preferences::Configuration` instance initialized at boot

### Testing Setup

- Specs require a generated dummy app (`spec/dummy/`); run `rake test_app` to generate it
- `spec/spec_helper.rb` loads dotenv, the dummy app environment, and `spree_dev_tools` RSpec helpers
- HTTP calls are stubbed with WebMock in `dhl_express_client_spec.rb`
- Use `instance_double` for Spree objects (`Spree::Stock::Package`, etc.) to avoid loading the full stack

### RuboCop Configuration

- Target Ruby 3.3, `rubocop-rails` plugin enabled
- Line length max: 150
- `Style/Documentation` and `Style/FrozenStringLiteralComment` are disabled
- `spec/dummy/` and `lib/generators/` are excluded from linting
