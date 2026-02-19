require 'net/http'
require 'uri'
require 'json'
require 'base64'

module SpreeMydhl
  class DhlExpressClient
    class ApiError < StandardError; end

    PRODUCTION_BASE_URL = 'https://express.api.dhl.com/mydhlapi'.freeze
    SANDBOX_BASE_URL    = 'https://express.api.dhl.com/mydhlapi/test'.freeze

    def initialize(api_key:, api_secret:, account_number:, origin_country_code:,
                   origin_postal_code:, origin_city_name:, destination_country_code:,
                   destination_postal_code:, destination_city_name:, weight:,
                   length:, width:, height:, unit_of_measurement: 'metric',
                   currency: 'USD', sandbox: false, product_code: nil,
                   customs_declarable: nil)
      @api_key                  = api_key
      @api_secret               = api_secret
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
      @product_code             = product_code
      @customs_declarable       = customs_declarable
    end

    def cheapest_rate
      data = fetch_rates
      return nil if data.nil?

      products = data['products']
      return nil if products.nil? || products.empty?

      if @product_code.present?
        products = products.select { |p| p['productCode'] == @product_code }
        return nil if products.empty?
      end

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
        raise ApiError, "DHL API returned HTTP #{response.code}: #{response.body.to_s[0, 200]}"
      end

      JSON.parse(response.body)
    rescue ApiError => e
      Rails.logger.error("[SpreeMydhl] DHL API error: #{e.message}")
      Rails.logger.debug { Array(e.backtrace).first(5).join("\n") }
      nil
    rescue StandardError => e
      Rails.logger.error("[SpreeMydhl] DHL request failed: #{e.class}: #{e.message}")
      Rails.logger.debug { Array(e.backtrace).first(5).join("\n") }
      nil
    end

    def build_uri
      base_url = @sandbox ? SANDBOX_BASE_URL : PRODUCTION_BASE_URL
      uri = URI("#{base_url}/rates")
      uri.query = URI.encode_www_form(query_params.reject { |_, v| v.to_s.strip.empty? })
      uri
    end

    def build_request(uri)
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Basic #{Base64.strict_encode64("#{@api_key}:#{@api_secret}")}"
      request['Accept']        = 'application/json'
      request['User-Agent']    = "spree_mydhl/#{SpreeMydhl::VERSION}"
      request
    end

    def query_params
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
        isCustomsDeclarable:        customs_declarable?,
        nextBusinessDay:            true,
        requestedCurrencyCode:      @currency
      }
    end

    def customs_declarable?
      return @customs_declarable unless @customs_declarable.nil?

      @origin_country_code.upcase != @destination_country_code.upcase
    end

    def planned_shipping_date
      Date.current.iso8601
    end
  end
end
