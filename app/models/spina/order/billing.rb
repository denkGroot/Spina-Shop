module Spina
  class Order < ApplicationRecord
    def sub_total
      if prices_include_tax
        order_items.inject(BigDecimal(0)) { |t, i| t + i.total / i.tax_modifier }
      else
        order_items.inject(BigDecimal(0)) { |t, i| t + i.total }
      end
    end

    def sub_total_including_tax
      sub_total + tax_amount
    end

    def delivery_price
      read_attribute(:delivery_price) || delivery_option.try(:price_for_order, self) || BigDecimal(0)
    end

    def delivery_tax_rate
      read_attribute(:delivery_tax_rate) || delivery_option.try(:tax_group).try(:tax_rate_for_order, self) || BigDecimal(0)
    end

    def billing_first_name
      first_name
    end

    def billing_last_name
      last_name
    end

    # Total of the order
    def total
      sub_total + tax_amount + delivery_price
    end

    def tax_amount
      tax_amount_by_rates.inject(BigDecimal(0)) { |t, r| t + r[1][:tax_amount] }
    end

    def tax_amount_by_rates
      if prices_include_tax
        rates = order_items.inject({}) do |h, item|
          rate = h[item.tax_rate] ||= { tax_amount: BigDecimal(0), total: BigDecimal(0) }
          rate[:total] += item.total / item.tax_modifier
          rate[:tax_amount] += item.total - (item.total / item.tax_modifier)
          h
        end
      else
        rates = order_items.inject({}) do |h, item|
          rate = h[item.tax_rate] ||= { tax_amount: BigDecimal(0), total: BigDecimal(0) }
          rate[:total] += item.total
          h
        end

        rates.each do |rate|
          rate[1][:tax_amount] = rate[1][:total] * (BigDecimal(rate[0]) / BigDecimal(100))
        end
      end

      rates.sort{|x, y| y[0] <=> x[0]}.to_h
    end
  end
end