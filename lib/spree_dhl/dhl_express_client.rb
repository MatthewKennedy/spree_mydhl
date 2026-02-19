require 'net/http'
require 'uri'
require 'json'
require 'base64'

module SpreeDhl
  class DhlExpressClient
    class ApiError < StandardError; end

    PRODUCTION_BASE_URL = 'https://express.api.dhl.com/mydhlapi'.freeze
    SANDBOX_BASE_URL    = 'https://express.api.dhl.com/mydhlapi/test'.freeze

    def initialize(username:, password:, account_number:, origin_country_code:,
                   origin_postal_code:, origin_city_name:, destination_country_code:,
                   destination_postal_code:, destination_city_name:, weight:,
                   length:, width:, height:, unit_of_measurement: 'metric',
                   currency: 'USD', sandbox: false)
      @username                 = username
      @password                 = password
      @account_number           = account_number
      @origin_country_code      = origin_country_code
      @origin_postal_code       = origin_postal_code
      @origin_city_name         = origin_city_name
      @destination_country_code = destination_country_code
      @destination_postal_code  = destination_postal_code
      @destination_city_name    = destination_city_name
      @weight                   = weight
      @length                   = length
      @width                    = width
      @height                   = height
      @unit_of_measurement      = unit_of_measurement
      @currency                 = currency
      @sandbox                  = sandbox
    end

    def cheapest_rate
      data = fetch_rates
      return nil if data.nil?

      products = data['products']
      return nil if products.nil? || products.empty?

      prices = products.filter_map do |product|
        total_prices = product['totalPrice']
        next unless total_prices.is_a?(Array)

        billed = total_prices.find { |p| p['currencyType'] == 'BILLC' }
        billed&.fetch('price', nil)&.to_f
      end

      prices.empty? ? nil : prices.min
    end

    private

    def fetch_rates
      uri = build_uri
      request = build_request(uri)

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise ApiError, "DHL API returned HTTP #{response.code}: #{response.body}"
      end

      JSON.parse(response.body)
    rescue ApiError => e
      Rails.logger.error("[SpreeDhl] DHL API error: #{e.message}")
      nil
    rescue StandardError => e
      Rails.logger.error("[SpreeDhl] DHL request failed: #{e.class}: #{e.message}")
      nil
    end

    def build_uri
      base_url = @sandbox ? SANDBOX_BASE_URL : PRODUCTION_BASE_URL
      uri = URI("#{base_url}/rates")
      uri.query = URI.encode_www_form(query_params)
      uri
    end

    def build_request(uri)
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Basic #{Base64.strict_encode64("#{@username}:#{@password}")}"
      request['Accept']        = 'application/json'
      request
    end

    def query_params
      is_customs_declarable = @origin_country_code.upcase != @destination_country_code.upcase

      {
        accountNumber:              @account_number,
        originCountryCode:          @origin_country_code,
        originPostalCode:           @origin_postal_code,
        originCityName:             @origin_city_name,
        destinationCountryCode:     @destination_country_code,
        destinationPostalCode:      @destination_postal_code,
        destinationCityName:        @destination_city_name,
        weight:                     @weight.round(3),
        length:                     @length.round(2),
        width:                      @width.round(2),
        height:                     @height.round(2),
        plannedShippingDate:        planned_shipping_date,
        unitOfMeasurement:          @unit_of_measurement,
        isCustomsDeclarable:        is_customs_declarable,
        nextBusinessDay:            false,
        requestedCurrencyCode:      @currency
      }
    end

    def planned_shipping_date
      date = Date.today
      date += 2 if date.saturday?
      date += 1 if date.sunday?
      date.iso8601
    end
  end
end
