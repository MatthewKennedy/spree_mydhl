import '@hotwired/turbo-rails'
import { Application } from '@hotwired/stimulus'

let application

if (typeof window.Stimulus === "undefined") {
  application = Application.start()
  application.debug = false
  window.Stimulus = application
} else {
  application = window.Stimulus
}

import SpreeDhlController from 'spree_dhl/controllers/spree_dhl_controller' 

application.register('spree_dhl', SpreeDhlController)