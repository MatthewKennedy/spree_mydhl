module Spree
  module Calculator::Shipping
    class DhlExpress < ShippingCalculator
      PREFERENCE_ORDER = %i[
        api_key
        api_secret
        account_number
        stock_location_id
        product_code
        unit_of_measurement
        currency
        sandbox
        customs_declarable
        minimum_weight
        maximum_weight
      ].freeze

      UNIT_OF_MEASUREMENT_OPTIONS = %w[metric imperial].freeze

      PRODUCT_CODE_OPTIONS = [
        ['Any (cheapest)',            nil],
        ['P — Express Worldwide',     'P'],
        ['D — Express Worldwide Doc', 'D'],
        ['K — Express 9:00',          'K'],
        ['W — Express 10:30',         'W'],
        ['T — Express 12:00',         'T'],
        ['Y — Express 12:00 Doc',     'Y'],
        ['H — Economy Select',        'H'],
        ['N — Domestic Express',      'N']
      ].freeze

      preference :api_key,             :string
      preference :api_secret,          :password
      preference :account_number,      :string
      preference :stock_location_id,   :integer
      preference :unit_of_measurement, :string,  default: UNIT_OF_MEASUREMENT_OPTIONS.first
      preference :currency,            :string,  default: -> { Spree::Store.default.default_currency }
      preference :sandbox,             :boolean, default: false
      preference :product_code,        :string,  default: nil, nullable: true
      preference :customs_declarable,  :boolean, default: nil, nullable: true
      preference :minimum_weight,      :decimal, default: nil, nullable: true
      preference :maximum_weight,      :decimal, default: nil, nullable: true
      preference :markup_percentage,   :decimal, default: nil, nullable: true
      preference :handling_fee,        :decimal, default: nil, nullable: true
      preference :cache_ttl_minutes,   :integer, default: 10

      def self.description
        'MyDHL Live Rates'
      end

      def available?(package)
        if required_preferences_blank?
          Rails.logger.debug('[SpreeMydhl] available? = false: one or more required preferences are blank')
          return false
        end

        if preferred_minimum_weight.present? && preferred_maximum_weight.present? &&
           preferred_minimum_weight.to_f > preferred_maximum_weight.to_f
          Rails.logger.warn('[SpreeMydhl] minimum_weight exceeds maximum_weight — no package can qualify; check shipping method configuration')
          return false
        end

        stock_location = package.stock_location
        if stock_location.nil? || stock_location.id.to_i != preferred_stock_location_id.to_i
          Rails.logger.debug('[SpreeMydhl] available? = false: package stock location does not match configured stock location')
          return false
        end

        address = package.order.ship_address
        if address.nil?
          Rails.logger.debug('[SpreeMydhl] available? = false: ship_address is nil')
          return false
        end

        if address.country&.iso.blank?
          Rails.logger.debug('[SpreeMydhl] available? = false: ship_address country ISO is blank')
          return false
        end

        weight = package_weight(package)

        if preferred_minimum_weight.present? && weight < preferred_minimum_weight.to_f
          Rails.logger.debug("[SpreeMydhl] available? = false: weight #{weight} below minimum #{preferred_minimum_weight}")
          return false
        end

        if preferred_maximum_weight.present? && weight > preferred_maximum_weight.to_f
          Rails.logger.debug("[SpreeMydhl] available? = false: weight #{weight} above maximum #{preferred_maximum_weight}")
          return false
        end

        true
      end

      def compute_package(package)
        return nil unless available?(package)

        stock_location = package.stock_location
        origin_country = stock_location.country_iso

        if origin_country.blank?
          Rails.logger.debug('[SpreeMydhl] compute_package -> nil: stock location has no country ISO')
          return nil
        end

        origin_postal = stock_location.zipcode.to_s
        origin_city   = stock_location.city.to_s

        destination  = package.order.ship_address
        dest_country = destination.country.iso
        dest_postal  = destination.zipcode.to_s
        dest_city    = destination.city.to_s

        weight     = package_weight(package)
        dimensions = package_dimensions(package)
        currency   = effective_currency(package)
        cache_key  = build_cache_key(origin_country, origin_postal, dest_country, dest_postal, dest_city, weight, dimensions, currency)

        rate = Rails.cache.fetch(cache_key, expires_in: preferred_cache_ttl_minutes.minutes, skip_nil: true) do
          client = SpreeMydhl::DhlExpressClient.new(
            api_key:                  preferred_api_key,
            api_secret:               preferred_api_secret,
            account_number:           preferred_account_number,
            origin_country_code:      origin_country,
            origin_postal_code:       origin_postal,
            origin_city_name:         origin_city,
            destination_country_code: dest_country,
            destination_postal_code:  dest_postal,
            destination_city_name:    dest_city,
            weight:                   weight,
            length:                   dimensions[:length],
            width:                    dimensions[:width],
            height:                   dimensions[:height],
            unit_of_measurement:      preferred_unit_of_measurement,
            currency:                 currency,
            sandbox:                  preferred_sandbox,
            product_code:             preferred_product_code,
            customs_declarable:       preferred_customs_declarable
          )
          client.cheapest_rate
        end

        rate = apply_markup(rate)
        Rails.logger.debug("[SpreeMydhl] compute_package -> #{rate.inspect} (#{dest_country} #{dest_postal})")
        rate
      rescue StandardError => e
        Rails.logger.error("[SpreeMydhl] compute_package failed: #{e.class}: #{e.message}")
        Rails.logger.debug { Array(e.backtrace).first(5).join("\n") }
        nil
      end

      private

      def required_preferences_blank?
        [
          preferred_api_key,
          preferred_api_secret,
          preferred_account_number,
          preferred_stock_location_id
        ].any?(&:blank?)
      end

      def package_weight(package)
        @package_weights ||= {}
        @package_weights[package.object_id] ||= begin
          w = package.weight
          w.positive? ? w.to_f : 0.1
        end
      end

      # Computes package dimensions from variant attributes.
      # Variant depth/width/height and package weight must be stored in units that
      # match the configured unit_of_measurement preference (metric: cm/kg, imperial: in/lb).
      # No automatic unit conversion is applied.
      def package_dimensions(package)
        max_length   = 0.0
        max_width    = 0.0
        total_height = 0.0

        package.contents.each do |content|
          variant  = content.variant
          quantity = [content.quantity.to_i, 1].max
          max_length   = [max_length, variant.depth.to_f].max
          max_width    = [max_width, variant.width.to_f].max
          total_height += variant.height.to_f * quantity
        end

        {
          length: max_length.positive? ? max_length : 1.0,
          width:  max_width.positive?  ? max_width  : 1.0,
          height: total_height.positive? ? total_height : 1.0
        }
      end

      def effective_currency(package)
        preferred_currency.presence || package.order.currency || package.order.store&.default_currency
      end

      def apply_markup(rate)
        return nil if rate.nil?

        rate = rate * (1 + preferred_markup_percentage.to_f / 100.0) if preferred_markup_percentage.present?
        rate = rate + preferred_handling_fee.to_f                    if preferred_handling_fee.present?
        rate.round(2)
      end

      def build_cache_key(origin_country, origin_postal, dest_country, dest_postal, dest_city, weight, dimensions, currency)
        [
          'spree_mydhl',
          'rates',
          preferred_account_number,
          preferred_stock_location_id,
          preferred_unit_of_measurement,
          preferred_product_code,
          preferred_customs_declarable,
          origin_country,
          origin_postal,
          dest_country,
          dest_postal,
          dest_city,
          weight.round(3),
          dimensions[:length].round(2),
          dimensions[:width].round(2),
          dimensions[:height].round(2),
          currency,
          Date.current.iso8601
        ].join('/')
      end
    end
  end
end
