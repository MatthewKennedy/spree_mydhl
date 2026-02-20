require 'spec_helper'

RSpec.describe Spree::Calculator::Shipping::DhlExpress do
  subject(:calculator) { described_class.new }

  let(:origin_country)  { build(:country, iso: 'US') }
  let(:stock_location) do
    instance_double(Spree::StockLocation,
                    id:          1,
                    country_iso: 'US',
                    zipcode:     '10001',
                    city:        'New York')
  end

  let(:dest_country) { build(:country, iso: 'DE') }
  let(:address)      { build(:address, country: dest_country, zipcode: '10115', city: 'Berlin') }
  let(:store)        { instance_double(Spree::Store, default_currency: 'EUR') }
  let(:order)        { build(:order, ship_address: address, currency: 'USD') }
  let(:variant)      { build(:variant, depth: 10.0, width: 5.0, height: 3.0, weight: 1.0) }
  let(:content)      { instance_double(Spree::Stock::ContentItem, variant: variant, quantity: 1) }
  let(:package) do
    instance_double(Spree::Stock::Package,
                    order:          order,
                    weight:         1.5,
                    contents:       [content],
                    stock_location: stock_location)
  end

  def set_required_preferences(calc = calculator)
    calc.preferred_api_key           = 'testuser'
    calc.preferred_api_secret        = 'testpass'
    calc.preferred_account_number    = '123456789'
    calc.preferred_stock_location_id = 1
  end

  describe '.description' do
    it 'returns MyDHL Live Rates' do
      expect(described_class.description).to eq('MyDHL Live Rates')
    end
  end

  describe '#available?' do
    context 'when all required preferences are set and address is present' do
      before { set_required_preferences }

      it 'returns true' do
        expect(calculator.available?(package)).to be true
      end
    end

    context 'when api_key is blank' do
      before do
        set_required_preferences
        calculator.preferred_api_key = ''
      end

      it 'returns false' do
        expect(calculator.available?(package)).to be false
      end
    end

    context 'when api_secret is blank' do
      before do
        set_required_preferences
        calculator.preferred_api_secret = nil
      end

      it 'returns false' do
        expect(calculator.available?(package)).to be false
      end
    end

    context 'when account_number is blank' do
      before do
        set_required_preferences
        calculator.preferred_account_number = ''
      end

      it 'returns false' do
        expect(calculator.available?(package)).to be false
      end
    end

    context 'when stock_location_id is blank' do
      before do
        set_required_preferences
        calculator.preferred_stock_location_id = nil
      end

      it 'returns false' do
        expect(calculator.available?(package)).to be false
      end
    end

    context 'when minimum_weight exceeds maximum_weight' do
      before do
        set_required_preferences
        calculator.preferred_minimum_weight = 5.0
        calculator.preferred_maximum_weight = 2.0
      end

      it 'returns false' do
        expect(calculator.available?(package)).to be false
      end

      it 'logs a warning about the misconfiguration' do
        expect(Rails.logger).to receive(:warn).with(/minimum_weight exceeds maximum_weight/)
        calculator.available?(package)
      end
    end

    context 'when package is from a different stock location' do
      let(:other_stock_location) { instance_double(Spree::StockLocation, id: 99) }
      let(:other_package) do
        instance_double(Spree::Stock::Package,
                        order:          order,
                        weight:         1.5,
                        contents:       [content],
                        stock_location: other_stock_location)
      end

      before { set_required_preferences }

      it 'returns false' do
        expect(calculator.available?(other_package)).to be false
      end
    end

    context 'when package stock_location is nil' do
      let(:package_no_location) do
        instance_double(Spree::Stock::Package,
                        order:          order,
                        weight:         1.5,
                        contents:       [content],
                        stock_location: nil)
      end

      before { set_required_preferences }

      it 'returns false' do
        expect(calculator.available?(package_no_location)).to be false
      end
    end

    context 'when ship_address is nil' do
      before do
        set_required_preferences
        allow(order).to receive(:ship_address).and_return(nil)
      end

      it 'returns false' do
        expect(calculator.available?(package)).to be false
      end
    end

    context 'when ship_address country ISO is blank' do
      let(:country_no_iso) { build(:country, iso: '') }
      let(:address_no_iso) { build(:address, country: country_no_iso) }
      let(:order_no_iso)   { build(:order, ship_address: address_no_iso) }
      let(:package_no_iso) do
        instance_double(Spree::Stock::Package,
                        order:          order_no_iso,
                        weight:         1.0,
                        contents:       [],
                        stock_location: stock_location)
      end

      before { set_required_preferences }

      it 'returns false' do
        expect(calculator.available?(package_no_iso)).to be false
      end
    end

    context 'when weight is below minimum_weight' do
      before do
        set_required_preferences
        calculator.preferred_minimum_weight = 2.0
      end

      it 'returns false' do
        expect(calculator.available?(package)).to be false
      end
    end

    context 'when weight is above maximum_weight' do
      before do
        set_required_preferences
        calculator.preferred_maximum_weight = 1.0
      end

      it 'returns false' do
        expect(calculator.available?(package)).to be false
      end
    end

    context 'when weight is within min/max bounds' do
      before do
        set_required_preferences
        calculator.preferred_minimum_weight = 1.0
        calculator.preferred_maximum_weight = 2.0
      end

      it 'returns true' do
        expect(calculator.available?(package)).to be true
      end
    end
  end

  describe '#compute_package' do
    before { set_required_preferences }

    context 'when available? returns false' do
      before { calculator.preferred_api_key = '' }

      it 'returns nil without calling the client' do
        expect(SpreeMydhl::DhlExpressClient).not_to receive(:new)
        expect(calculator.compute_package(package)).to be_nil
      end
    end

    context 'when the client returns a cheapest rate' do
      before do
        allow(Rails.cache).to receive(:fetch).and_yield
        client_double = instance_double(SpreeMydhl::DhlExpressClient, cheapest_rate: 42.50)
        allow(SpreeMydhl::DhlExpressClient).to receive(:new).and_return(client_double)
      end

      it 'returns the price as a Float' do
        expect(calculator.compute_package(package)).to eq(42.50)
      end

      it 'derives origin details from the package stock location' do
        expect(SpreeMydhl::DhlExpressClient).to receive(:new).with(
          hash_including(
            origin_country_code: 'US',
            origin_postal_code:  '10001',
            origin_city_name:    'New York'
          )
        ).and_return(instance_double(SpreeMydhl::DhlExpressClient, cheapest_rate: 42.50))

        calculator.compute_package(package)
      end

      it 'passes credentials to the client' do
        expect(SpreeMydhl::DhlExpressClient).to receive(:new).with(
          hash_including(
            api_key:        'testuser',
            api_secret:     'testpass',
            account_number: '123456789'
          )
        ).and_return(instance_double(SpreeMydhl::DhlExpressClient, cheapest_rate: 42.50))

        calculator.compute_package(package)
      end

      it 'passes correct destination details to the client' do
        expect(SpreeMydhl::DhlExpressClient).to receive(:new).with(
          hash_including(
            destination_country_code: 'DE',
            destination_postal_code:  '10115',
            destination_city_name:    'Berlin'
          )
        ).and_return(instance_double(SpreeMydhl::DhlExpressClient, cheapest_rate: 42.50))

        calculator.compute_package(package)
      end

      it 'passes the order currency to the client when no currency preference is set' do
        expect(SpreeMydhl::DhlExpressClient).to receive(:new).with(
          hash_including(currency: 'USD')
        ).and_return(instance_double(SpreeMydhl::DhlExpressClient, cheapest_rate: 42.50))

        calculator.compute_package(package)
      end

      it 'uses the currency preference over the order currency when set' do
        calculator.preferred_currency = 'GBP'

        expect(SpreeMydhl::DhlExpressClient).to receive(:new).with(
          hash_including(currency: 'GBP')
        ).and_return(instance_double(SpreeMydhl::DhlExpressClient, cheapest_rate: 42.50))

        calculator.compute_package(package)
      end

      it 'falls back to the order store currency when order has no currency' do
        calculator.preferred_currency = nil
        allow(order).to receive(:currency).and_return(nil)
        allow(order).to receive(:store).and_return(store)

        expect(SpreeMydhl::DhlExpressClient).to receive(:new).with(
          hash_including(currency: 'EUR')
        ).and_return(instance_double(SpreeMydhl::DhlExpressClient, cheapest_rate: 42.50))

        calculator.compute_package(package)
      end

      it 'passes the product_code preference to the client when set' do
        calculator.preferred_product_code = 'P'

        expect(SpreeMydhl::DhlExpressClient).to receive(:new).with(
          hash_including(product_code: 'P')
        ).and_return(instance_double(SpreeMydhl::DhlExpressClient, cheapest_rate: 42.50))

        calculator.compute_package(package)
      end

      it 'passes customs_declarable preference to the client when set' do
        calculator.preferred_customs_declarable = false

        expect(SpreeMydhl::DhlExpressClient).to receive(:new).with(
          hash_including(customs_declarable: false)
        ).and_return(instance_double(SpreeMydhl::DhlExpressClient, cheapest_rate: 42.50))

        calculator.compute_package(package)
      end
    end

    context 'when the stock location has no country ISO' do
      let(:stock_location) do
        instance_double(Spree::StockLocation,
                        id:          1,
                        country_iso: '',
                        zipcode:     '10001',
                        city:        'New York')
      end

      it 'returns nil without calling the client' do
        expect(SpreeMydhl::DhlExpressClient).not_to receive(:new)
        expect(calculator.compute_package(package)).to be_nil
      end

      it 'logs a debug message' do
        allow(Rails.logger).to receive(:debug)
        expect(Rails.logger).to receive(:debug).with(/stock location has no country ISO/)
        calculator.compute_package(package)
      end
    end

    context 'when the client returns nil (API error)' do
      before do
        allow(Rails.cache).to receive(:fetch).and_yield
        client_double = instance_double(SpreeMydhl::DhlExpressClient, cheapest_rate: nil)
        allow(SpreeMydhl::DhlExpressClient).to receive(:new).and_return(client_double)
      end

      it 'returns nil' do
        expect(calculator.compute_package(package)).to be_nil
      end
    end

    context 'when the client raises an exception' do
      before do
        allow(Rails.cache).to receive(:fetch).and_yield
        allow(SpreeMydhl::DhlExpressClient).to receive(:new).and_raise(StandardError, 'network down')
      end

      it 'returns nil and does not propagate the error' do
        expect(calculator.compute_package(package)).to be_nil
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:error).with(/compute_package failed.*network down/)
        calculator.compute_package(package)
      end
    end

    context 'caching behaviour' do
      # Force factory objects to be evaluated before the it block sets up cache mocks.
      # build(:variant) internally calls Rails.cache.fetch('default_store'); memoizing
      # here ensures that call completes before any stub is installed.
      before { [variant, content] }

      it 'uses Rails.cache with a 10-minute expiry and skip_nil' do
        expect(Rails.cache).to receive(:fetch).with(
          a_string_starting_with('spree_mydhl/rates/'),
          expires_in: 10.minutes,
          skip_nil:   true
        ).and_return(29.99)

        expect(calculator.compute_package(package)).to eq(29.99)
      end

      it 'skips the client call on a cache hit' do
        allow(Rails.cache).to receive(:fetch).with(
          a_string_starting_with('spree_mydhl/rates/'),
          expires_in: 10.minutes,
          skip_nil:   true
        ).and_return(29.99)

        expect(SpreeMydhl::DhlExpressClient).not_to receive(:new)
        calculator.compute_package(package)
      end

      it 'includes customs_declarable in the cache key so different overrides are not conflated' do
        keys = []
        allow(Rails.cache).to receive(:fetch) { |key, **| keys << key; 10.0 }

        calculator.preferred_customs_declarable = true
        calculator.compute_package(package)

        calculator.preferred_customs_declarable = false
        calculator.compute_package(package)

        expect(keys.uniq.length).to eq(2)
      end

      it 'uses Date.current (Rails timezone) for the cache key date segment' do
        allow(Date).to receive(:current).and_return(Date.new(2026, 2, 20))
        allow(Rails.cache).to receive(:fetch) { |key, **| key }

        key = calculator.compute_package(package)
        expect(key).to include('2026-02-20')
      end
    end
  end
end
