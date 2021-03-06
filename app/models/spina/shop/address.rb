module Spina::Shop
  class Address < ApplicationRecord
    belongs_to :country
    belongs_to :customer

    validates :street1, :postal_code, :city, presence: true

    scope :general, -> { where.not(address_type: %w(billing delivery)) }
    scope :billing, -> { where(address_type: 'billing') }
    scope :delivery, -> { where(address_type: 'delivery') }

    def name
      read_attribute(:name).presence || full_name
    end

    def full_name
      "#{first_name} #{last_name}".strip
    end

    def address
      "#{street1} #{house_number} #{house_number_addition}".strip
    end
  end
end