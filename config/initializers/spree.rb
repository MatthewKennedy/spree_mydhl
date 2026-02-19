Rails.application.config.after_initialize do
  Spree.calculators.shipping_methods << Spree::Calculator::Shipping::DhlExpress
end
