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
        preference :currency,            :string
        preference :sandbox,             :boolean, default: false

        def self.description
          'DHL Express'
        end

        def available?(package)
          return false if required_preferences_blank?

          address = package.order.ship_address
          return false if address.nil?
          return false if address.country&.iso.blank?

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

          cache_key = build_cache_key(dest_country, dest_postal, dest_city, weight, dimensions)

          Rails.cache.fetch(cache_key, expires_in: 10.minutes) do
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
              currency:                 effective_currency,
              sandbox:                  preferred_sandbox
            )
            client.cheapest_rate
          end
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

        def effective_currency
          preferred_currency.presence || Spree::Config.currency
        end

        def build_cache_key(dest_country, dest_postal, dest_city, weight, dimensions)
          [
            'spree_dhl',
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
            Date.today.iso8601
          ].join('/')
        end
    end
  end
end

