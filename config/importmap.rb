pin 'application-spree-dhl', to: 'spree_dhl/application.js', preload: false

pin_all_from SpreeDhl::Engine.root.join('app/javascript/spree_dhl/controllers'),
             under: 'spree_dhl/controllers',
             to:    'spree_dhl/controllers',
             preload: 'application-spree-dhl'
