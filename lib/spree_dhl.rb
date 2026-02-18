require 'spree'
require 'spree_extension'
require 'spree_dhl/engine'
require 'spree_dhl/version'
require 'spree_dhl/configuration'
require 'spree_dhl/dhl_express_client'

module SpreeDhl
  mattr_accessor :queue

  def self.queue
    @@queue ||= Spree.queues.default
  end
end
