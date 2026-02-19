require 'spec_helper'

RSpec.describe Spree::Calculator::Shipping::DhlExpress do
  subject(:calculator) { described_class.new }

  let(:country) { build(:country, iso: 'DE') }
  let(:address) { build(:address, country: country, zipcode: '10115', city: 'Berlin') }
  let(:order)   { build(:order, ship_address: address, currency: 'USD') }
  let(:variant) { build(:variant, depth: 10.0, width: 5.0, height: 3.0, weight: 1.0) }
  let(:content) { instance_double(Spree::Stock::ContentItem, variant: variant, quantity: 1) }
  let(:package) do
    instance_double(Spree::Stock::Package,
                    order:    order,
                    weight:   1.5,
                    contents: [content])
  end

  def set_required_preferences(calc = calculator)
    calc.preferred_username            = 'testuser'
    calc.preferred_password            = 'testpass'
    calc.preferred_account_number      = '123456789'
    calc.preferred_origin_country_code = 'US'
    calc.preferred_origin_postal_code  = '10001'
    calc.preferred_origin_city_name    = 'New York'
  end

  describe '.description' do
    it 'returns DHL Express' do
      expect(described_class.description).to eq('DHL Express')
    end
  end

  describe '#available?' do
    context 'when all required preferences are set and address is present' do
      before { set_required_preferences }

      it 'returns true' do
        expect(calculator.available?(package)).to be true
      end
    end

    context 'when username is blank' do
      before do
        set_required_preferences
        calculator.preferred_username = ''
      end

      it 'returns false' do
        expect(calculator.available?(package)).to be false
      end
    end

    context 'when password is blank' do
      before do
        set_required_preferences
        calculator.preferred_password = nil
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

    context 'when origin_country_code is blank' do
      before do
        set_required_preferences
        calculator.preferred_origin_country_code = ''
      end

      it 'returns false' do
        expect(calculator.available?(package)).to be false
      end
    end

    context 'when origin_postal_code is blank' do
      before do
        set_required_preferences
        calculator.preferred_origin_postal_code = ''
      end

      it 'returns false' do
        expect(calculator.available?(package)).to be false
      end
    end

    context 'when origin_city_name is blank' do
      before do
        set_required_preferences
        calculator.preferred_origin_city_name = ''
      end

      it 'returns true (city name is optional)' do
        expect(calculator.available?(package)).to be true
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

    context 'when ship_address country ISO is blank' do
      let(:country_no_iso) { build(:country, iso: '') }
      let(:address_no_iso) { build(:address, country: country_no_iso) }
      let(:order_no_iso)   { build(:order, ship_address: address_no_iso) }
      let(:package_no_iso) do
        instance_double(Spree::Stock::Package,
                        order:    order_no_iso,
                        weight:   1.0,
                        contents: [])
      end

      before { set_required_preferences }

      it 'returns false' do
        expect(calculator.available?(package_no_iso)).to be false
      end
    end
  end

  describe '#compute_package' do
    before { set_required_preferences }

    context 'when available? returns false' do
      before { calculator.preferred_username = '' }

      it 'returns nil without calling the client' do
        expect(SpreeDhl::DhlExpressClient).not_to receive(:new)
        expect(calculator.compute_package(package)).to be_nil
      end
    end

    context 'when the client returns a cheapest rate' do
      before do
        allow(Rails.cache).to receive(:fetch).and_yield
        client_double = instance_double(SpreeDhl::DhlExpressClient, cheapest_rate: 42.50)
        allow(SpreeDhl::DhlExpressClient).to receive(:new).and_return(client_double)
      end

      it 'returns the price as a Float' do
        expect(calculator.compute_package(package)).to eq(42.50)
      end

      it 'passes correct origin preferences to the client' do
        expect(SpreeDhl::DhlExpressClient).to receive(:new).with(
          hash_including(
            username:            'testuser',
            password:            'testpass',
            account_number:      '123456789',
            origin_country_code: 'US',
            origin_postal_code:  '10001',
            origin_city_name:    'New York'
          )
        ).and_return(instance_double(SpreeDhl::DhlExpressClient, cheapest_rate: 42.50))

        calculator.compute_package(package)
      end

      it 'passes correct destination details to the client' do
        expect(SpreeDhl::DhlExpressClient).to receive(:new).with(
          hash_including(
            destination_country_code: 'DE',
            destination_postal_code:  '10115',
            destination_city_name:    'Berlin'
          )
        ).and_return(instance_double(SpreeDhl::DhlExpressClient, cheapest_rate: 42.50))

        calculator.compute_package(package)
      end

      it 'passes the order currency to the client when no currency preference is set' do
        expect(SpreeDhl::DhlExpressClient).to receive(:new).with(
          hash_including(currency: 'USD')
        ).and_return(instance_double(SpreeDhl::DhlExpressClient, cheapest_rate: 42.50))

        calculator.compute_package(package)
      end

      it 'uses the currency preference over the order currency when set' do
        calculator.preferred_currency = 'GBP'

        expect(SpreeDhl::DhlExpressClient).to receive(:new).with(
          hash_including(currency: 'GBP')
        ).and_return(instance_double(SpreeDhl::DhlExpressClient, cheapest_rate: 42.50))

        calculator.compute_package(package)
      end

      it 'passes next_business_day preference to the client' do
        calculator.preferred_next_business_day = true

        expect(SpreeDhl::DhlExpressClient).to receive(:new).with(
          hash_including(next_business_day: true)
        ).and_return(instance_double(SpreeDhl::DhlExpressClient, cheapest_rate: 42.50))

        calculator.compute_package(package)
      end

      it 'passes customs_declarable preference to the client when set' do
        calculator.preferred_customs_declarable = false

        expect(SpreeDhl::DhlExpressClient).to receive(:new).with(
          hash_including(customs_declarable: false)
        ).and_return(instance_double(SpreeDhl::DhlExpressClient, cheapest_rate: 42.50))

        calculator.compute_package(package)
      end
    end

    context 'when the client returns nil (API error)' do
      before do
        allow(Rails.cache).to receive(:fetch).and_yield
        client_double = instance_double(SpreeDhl::DhlExpressClient, cheapest_rate: nil)
        allow(SpreeDhl::DhlExpressClient).to receive(:new).and_return(client_double)
      end

      it 'returns nil' do
        expect(calculator.compute_package(package)).to be_nil
      end
    end

    context 'when the client raises an exception' do
      before do
        allow(Rails.cache).to receive(:fetch).and_yield
        allow(SpreeDhl::DhlExpressClient).to receive(:new).and_raise(StandardError, 'network down')
      end

      it 'returns nil and does not propagate the error' do
        expect(calculator.compute_package(package)).to be_nil
      end
    end

    context 'caching behaviour' do
      # Force factory objects to be evaluated before the it block sets up cache mocks.
      # build(:variant) internally calls Rails.cache.fetch('default_store'); memoizing
      # here ensures that call completes before any stub is installed.
      before { [variant, content] }

      it 'uses Rails.cache with a 10-minute expiry and skip_nil' do
        expect(Rails.cache).to receive(:fetch).with(
          a_string_starting_with('spree_dhlx/rates/'),
          expires_in: 10.minutes,
          skip_nil:   true
        ).and_return(29.99)

        expect(calculator.compute_package(package)).to eq(29.99)
      end

      it 'skips the client call on a cache hit' do
        allow(Rails.cache).to receive(:fetch).with(
          a_string_starting_with('spree_dhlx/rates/'),
          expires_in: 10.minutes,
          skip_nil:   true
        ).and_return(29.99)

        expect(SpreeDhl::DhlExpressClient).not_to receive(:new)
        calculator.compute_package(package)
      end
    end
  end
end
