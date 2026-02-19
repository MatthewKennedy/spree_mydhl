module Spree
  module Admin
    module BaseHelperDecorator
      def preference_field(object, form, key, i18n_scope: '')
        return super unless object.is_a?(Spree::Calculator::Shipping::DhlExpress)

        case key
        when :unit_of_measurement
          options = Spree::Calculator::Shipping::DhlExpress::UNIT_OF_MEASUREMENT_OPTIONS.map do |opt|
            [opt.capitalize, opt]
          end

          content_tag(:div, class: 'form-group') do
            form.label("preferred_#{key}", Spree.t(key, scope: i18n_scope, default: key.to_s.humanize)) +
              form.select("preferred_#{key}", options, {}, class: 'form-select form-control')
          end

        when :product_code
          content_tag(:div, class: 'form-group') do
            form.label("preferred_#{key}", Spree.t(:product_code)) +
              form.select("preferred_#{key}", Spree::Calculator::Shipping::DhlExpress::PRODUCT_CODE_OPTIONS,
                          { include_blank: false },
                          class: 'form-select form-control')
          end

        when :stock_location_id
          stock_locations = Spree::StockLocation.active.order(:name).pluck(:name, :id)

          content_tag(:div, class: 'form-group') do
            form.label("preferred_#{key}", Spree.t(:stock_location)) +
              form.select("preferred_#{key}", stock_locations, { include_blank: Spree.t(:select_stock_location) },
                          class: 'form-select form-control')
          end

        else
          super
        end
      end
    end
  end
end

Spree::Admin::BaseHelper.prepend(Spree::Admin::BaseHelperDecorator)
