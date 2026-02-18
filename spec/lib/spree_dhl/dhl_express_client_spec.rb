require 'spec_helper'
require 'webmock/rspec'

RSpec.describe SpreeDhl::DhlExpressClient do
  subject(:client) do
    described_class.new(
      username:                 'testuser',
      password:                 'testpass',
      account_number:           '123456789',
      origin_country_code:      'US',
      origin_postal_code:       '10001',
      origin_city_name:         'New York',
      destination_country_code: 'DE',
      destination_postal_code:  '10115',
      destination_city_name:    'Berlin',
      weight:                   1.5,
      length:                   10.0,
      width:                    5.0,
      height:                   3.0,
      unit_of_measurement:      'metric',
      currency:                 'USD',
      sandbox:                  true
    )
  end

  let(:api_base_url) { 'https://express.api.dhl.com/mydhlapi/test/rates' }

  let(:successful_response_body) do
    {
      products: [
        {
          productCode: 'P',
          productName: 'EXPRESS WORLDWIDE',
          totalPrice: [
            { currencyType: 'PULC', price: 30.00 },
            { currencyType: 'BILLC', price: 45.00 }
          ]
        },
        {
          productCode: 'D',
          productName: 'EXPRESS WORLDWIDE',
          totalPrice: [
            { currencyType: 'PULC', price: 20.00 },
            { currencyType: 'BILLC', price: 38.50 }
          ]
        }
      ]
    }.to_json
  end

  def stub_dhl_api(status: 200, body: successful_response_body)
    stub_request(:get, /express\.api\.dhl\.com/)
      .to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  describe '#cheapest_rate' do
    context 'with a successful response containing multiple products' do
      before { stub_dhl_api }

      it 'returns the minimum BILLC price as a Float' do
        expect(client.cheapest_rate).to eq(38.50)
      end
    end

    context 'with a successful response containing a single product' do
      let(:single_product_body) do
        {
          products: [
            {
              productCode: 'P',
              totalPrice: [
                { currencyType: 'BILLC', price: 55.00 }
              ]
            }
          ]
        }.to_json
      end

      before { stub_dhl_api(body: single_product_body) }

      it 'returns that product price' do
        expect(client.cheapest_rate).to eq(55.00)
      end
    end

    context 'with an empty products array' do
      before { stub_dhl_api(body: { products: [] }.to_json) }

      it 'returns nil' do
        expect(client.cheapest_rate).to be_nil
      end
    end

    context 'with products that have no BILLC price entry' do
      let(:no_billc_body) do
        {
          products: [
            {
              productCode: 'P',
              totalPrice: [
                { currencyType: 'PULC', price: 30.00 }
              ]
            }
          ]
        }.to_json
      end

      before { stub_dhl_api(body: no_billc_body) }

      it 'returns nil' do
        expect(client.cheapest_rate).to be_nil
      end
    end

    context 'with a 401 Unauthorized response' do
      before { stub_dhl_api(status: 401, body: '{"detail":"Unauthorized"}') }

      it 'returns nil' do
        expect(client.cheapest_rate).to be_nil
      end

      it 'logs an error' do
        expect(Rails.logger).to receive(:error).with(/DHL API error.*401/)
        client.cheapest_rate
      end
    end

    context 'with a 500 server error response' do
      before { stub_dhl_api(status: 500, body: '{"detail":"Internal Server Error"}') }

      it 'returns nil' do
        expect(client.cheapest_rate).to be_nil
      end

      it 'logs an error' do
        expect(Rails.logger).to receive(:error).with(/DHL API error.*500/)
        client.cheapest_rate
      end
    end

    context 'with a network connection error' do
      before do
        stub_request(:get, /express\.api\.dhl\.com/)
          .to_raise(Errno::ECONNREFUSED)
      end

      it 'returns nil' do
        expect(client.cheapest_rate).to be_nil
      end

      it 'logs an error' do
        expect(Rails.logger).to receive(:error).with(/DHL request failed/)
        client.cheapest_rate
      end
    end

    context 'with a connection timeout' do
      before do
        stub_request(:get, /express\.api\.dhl\.com/)
          .to_raise(Net::OpenTimeout)
      end

      it 'returns nil' do
        expect(client.cheapest_rate).to be_nil
      end
    end

    context 'using production URL when sandbox is false' do
      subject(:prod_client) do
        described_class.new(
          username:                 'testuser',
          password:                 'testpass',
          account_number:           '123456789',
          origin_country_code:      'US',
          origin_postal_code:       '10001',
          origin_city_name:         'New York',
          destination_country_code: 'DE',
          destination_postal_code:  '10115',
          destination_city_name:    'Berlin',
          weight:                   1.5,
          length:                   10.0,
          width:                    5.0,
          height:                   3.0,
          sandbox:                  false
        )
      end

      before do
        stub_request(:get, /express\.api\.dhl\.com\/mydhlapi\/rates/)
          .to_return(status: 200, body: successful_response_body, headers: { 'Content-Type' => 'application/json' })
      end

      it 'hits the production endpoint' do
        prod_client.cheapest_rate
        expect(WebMock).to have_requested(:get, /mydhlapi\/rates/).once
      end
    end

    context 'request structure' do
      before { stub_dhl_api }

      it 'sends Basic auth header' do
        client.cheapest_rate
        expect(WebMock).to have_requested(:get, /express\.api\.dhl\.com/)
          .with(headers: { 'Authorization' => 'Basic dGVzdHVzZXI6dGVzdHBhc3M=' })
      end

      it 'includes required query parameters' do
        client.cheapest_rate
        expect(WebMock).to have_requested(:get, /express\.api\.dhl\.com/).with(
          query: hash_including(
            'accountNumber'          => '123456789',
            'originCountryCode'      => 'US',
            'destinationCountryCode' => 'DE',
            'weight'                 => '1.5',
            'unitOfMeasurement'      => 'metric'
          )
        )
      end

      it 'sets isCustomsDeclarable to true for international shipments' do
        client.cheapest_rate
        expect(WebMock).to have_requested(:get, /express\.api\.dhl\.com/).with(
          query: hash_including('isCustomsDeclarable' => 'true')
        )
      end
    end
  end
end
