module Spina::Shop
  module Product::Pricing
    extend ActiveSupport::Concern

    included do
      before_validation :set_price_exceptions
    end

    def promotion?
      promotional_price.present?
    end

    def price
      promotional_price.presence || base_price
    end

    def price_for_store(store)
      # If there is no store, simply return price
      return price if store.nil?
      price_exception_for_store(store).try(:[], 'price')&.gsub(",", ".")&.to_d || price
    end

    def price_for_order(order)
      # Return the default price if we don't know anything about the order
      return price if order.nil? 

      # If no conversion is needed, simply return price
      price = price_for_customer(order)
      price_includes_tax = price_includes_tax_for_order(order)
      return price if price_includes_tax == order.prices_include_tax

      # Price modifier for unit price
      price_modifier = tax_group.price_modifier_for_order(order)

      # Calculate unit price based on price modifier
      unit_price = price_includes_tax ? price / price_modifier : price * price_modifier

      # Round to two decimals using bankers' rounding
      return unit_price.round(2, :half_even)
    end

    def price_for_customer(order)
      return price_for_store(order.store) if order.customer.nil?
      price_exception_for_customer(order.customer).try(:[], 'price')&.gsub(",", ".")&.to_d || price_for_store(order.store)
    end

    def price_includes_tax_for_order(order)
      return price_includes_tax if order.nil?
      price_exception = price_exception_for_customer(order.customer) || price_exception_for_store(order.store)
      if price_exception.present?
        ActiveRecord::Type::Boolean.new.cast(price_exception['price_includes_tax'])
      else
        price_includes_tax
      end
    end

    private

      def set_price_exceptions
        self[:price_exceptions] = {
          'stores' => (price_exceptions['stores'].keep_if{|e| e['price'].present? && e['store_id'].present?} if price_exceptions['stores'].try(:any?)),
          'customer_groups' => (price_exceptions['customer_groups'].keep_if{|e| e['price'].present? && e['customer_group_id'].present?} if price_exceptions['customer_groups'].try(:any?))
        }
      end

      # Get price exception based on Customer / CustomerGroup if available
      # Try the parent of one's CustomerGroup if present
      # Subgroups are always first
      def price_exception_for_customer(customer)
        return if customer&.customer_group_id.blank?
        [customer.customer_group_id, customer.customer_group.parent_id].find do |group_id|
          price_exceptions.try(:[], 'customer_groups').try(:find) do |h|
            return h if h["customer_group_id"].to_i == group_id
          end.presence
        end
      end

      # Get price exception based on Store
      def price_exception_for_store(store)
        return if store.nil?
        price_exceptions.try(:[], 'stores')&.find do |h|
          return h if h["store_id"].to_i == store.id
        end.presence
      end

  end
end