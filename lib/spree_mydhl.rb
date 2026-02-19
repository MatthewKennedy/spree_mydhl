require 'spree'
require 'spree_extension'
require 'spree_mydhl/engine'
require 'spree_mydhl/version'
require 'spree_mydhl/configuration'
require 'spree_mydhl/dhl_express_client'

module SpreeMydhl
  mattr_accessor :queue

  def self.queue
    @@queue ||= Spree.queues.default
  end
end
