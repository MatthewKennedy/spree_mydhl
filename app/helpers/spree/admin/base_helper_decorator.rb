module Spree
  module Admin
    module BaseHelperDecorator
      def preference_field(object, form, key, i18n_scope: '')
        if object.is_a?(Spree::Calculator::Shipping::DhlExpress) && key == :unit_of_measurement
          options = Spree::Calculator::Shipping::DhlExpress::UNIT_OF_MEASUREMENT_OPTIONS.map do |opt|
            [opt.capitalize, opt]
          end

          content_tag(:div, class: 'form-group') do
            form.label("preferred_#{key}", Spree.t(key, scope: i18n_scope, default: key.to_s.humanize)) +
              form.select("preferred_#{key}", options, {}, class: 'form-select form-control')
          end
        else
          super
        end
      end
    end
  end
end

Spree::Admin::BaseHelper.prepend(Spree::Admin::BaseHelperDecorator)
