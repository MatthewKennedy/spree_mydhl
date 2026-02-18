module Spree
  module Calculator::Shipping
    class DhlExpress < ShippingCalculator
        preference :username,            :string
        preference :password,            :string
        preference :account_number,      :string
        preference :origin_country_code, :string
        preference :origin_postal_code,  :string
        preference :origin_city_name,    :string
        preference :unit_of_measurement, :string, default: 'metric'
        preference :currency,            :string, default: -> { Spree::Store.default.default_currency }
        preference :sandbox,             :boolean, default: false

        preference :amount, :decimal, default: 0
        preference :minimum_weight, :decimal, default: nil, nullable: true
        preference :maximum_weight, :decimal, default: nil, nullable: true

        def self.description
          'DHL Express'
        end

        def available?(package)
          if required_preferences_blank?
            Rails.logger.debug('[SpreeDhl] available? = false: one or more required preferences are blank')
            return false
          end

          address = package.order.ship_address
          if address.nil?
            Rails.logger.debug('[SpreeDhl] available? = false: ship_address is nil')
            return false
          end

          if address.country&.iso.blank?
            Rails.logger.debug('[SpreeDhl] available? = false: ship_address country ISO is blank')
            return false
          end

          true
        end

        def compute_package(package)
          return nil unless available?(package)

          destination = package.order.ship_address
          dest_country  = destination.country.iso
          dest_postal   = destination.zipcode.to_s
          dest_city     = destination.city.to_s

          weight     = package_weight(package)
          dimensions = package_dimensions(package)

          currency  = effective_currency(package)
          cache_key = build_cache_key(dest_country, dest_postal, dest_city, weight, dimensions, currency)

          rate = Rails.cache.fetch(cache_key, expires_in: 10.minutes) do
            client = SpreeDhl::DhlExpressClient.new(
              username:                 preferred_username,
              password:                 preferred_password,
              account_number:           preferred_account_number,
              origin_country_code:      preferred_origin_country_code,
              origin_postal_code:       preferred_origin_postal_code,
              origin_city_name:         preferred_origin_city_name,
              destination_country_code: dest_country,
              destination_postal_code:  dest_postal,
              destination_city_name:    dest_city,
              weight:                   weight,
              length:                   dimensions[:length],
              width:                    dimensions[:width],
              height:                   dimensions[:height],
              unit_of_measurement:      preferred_unit_of_measurement,
              currency:                 currency,
              sandbox:                  preferred_sandbox
            )
            client.cheapest_rate
          end

          Rails.logger.debug("[SpreeDhl] compute_package -> #{rate.inspect} (#{dest_country} #{dest_postal})")
          rate
        rescue StandardError => e
          Rails.logger.error("[SpreeDhl] compute_package failed: #{e.class}: #{e.message}")
          nil
        end

        private

        def required_preferences_blank?
          [
            preferred_username,
            preferred_password,
            preferred_account_number,
            preferred_origin_country_code,
            preferred_origin_postal_code,
            preferred_origin_city_name
          ].any?(&:blank?)
        end

        def package_weight(package)
          weight = package.weight
          weight.positive? ? weight.to_f : 0.1
        end

        def package_dimensions(package)
          total_length = 0.0
          total_width  = 0.0
          total_height = 0.0

          package.contents.each do |content|
            variant = content.variant
            total_length += variant.depth.to_f
            total_width  += variant.width.to_f
            total_height += variant.height.to_f
          end

          {
            length: total_length.positive? ? total_length : 1.0,
            width:  total_width.positive?  ? total_width  : 1.0,
            height: total_height.positive? ? total_height : 1.0
          }
        end

        def effective_currency(package)
          preferred_currency.presence || package.order.currency || Spree::Config.currency
        end

        def build_cache_key(dest_country, dest_postal, dest_city, weight, dimensions, currency)
          [
            'spree_dhlx',
            'rates',
            preferred_origin_country_code,
            preferred_origin_postal_code,
            dest_country,
            dest_postal,
            dest_city,
            weight.round(3),
            dimensions[:length].round(2),
            dimensions[:width].round(2),
            dimensions[:height].round(2),
            currency,
            Date.today.iso8601
          ].join('/')
        end
    end
  end
end
