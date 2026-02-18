module SpreeDhl
  class BaseJob < Spree::BaseJob
    queue_as SpreeDhl.queue
  end
end
