module Spina::Shop
  module Product::Stock
    extend ActiveSupport::Concern

    included do
      attr_accessor :initial_stock_level

      has_many :stock_level_adjustments, dependent: :destroy
      has_many :in_stock_reminders, as: :orderable, dependent: :destroy

      has_many :product_locations, dependent: :restrict_with_exception
      has_many :locations, through: :product_locations

      accepts_nested_attributes_for :product_locations, allow_destroy: true, reject_if: proc { |attrs| attrs['location_code_id'].blank? }

      has_many :recounts, dependent: :destroy
      
      has_many :ordered_stock, dependent: :destroy
      has_many :stock_orders, through: :ordered_stock

      after_create :create_initial_stock_level_adjustment, if: :stock_enabled?

      scope :stock_forecast, -> { select('
        SUM(CASE WHEN "spina_shop_stock_level_adjustments"."created_at" > current_date - interval \'30 days\' AND "adjustment" < 0 AND order_item_id IS NOT NULL THEN "adjustment" ELSE 0 END) * -1 as past_30_days, 

        SUM(CASE WHEN "spina_shop_stock_level_adjustments"."created_at" > current_date - interval \'60 days\' AND order_item_id IS NOT NULL THEN "adjustment" ELSE 0 END) * -1 as past_60_days, 

        SUM(CASE WHEN "spina_shop_stock_level_adjustments"."created_at" > current_date - interval \'90 days\' AND order_item_id IS NOT NULL THEN "adjustment" ELSE 0 END) * -1 as past_90_days, 

        SUM(CASE WHEN "spina_shop_stock_level_adjustments"."created_at" > current_date - interval \'365 days\' AND order_item_id IS NOT NULL THEN "adjustment" ELSE 0 END) * -1 as past_365_days, 

        SUM(CASE WHEN "spina_shop_stock_level_adjustments"."created_at" > current_date - interval \'30 days\' AND "adjustment" < 0 AND order_item_id IS NOT NULL THEN 1 ELSE 0 END) as order_picking_30_days,

        SUM(CASE WHEN "spina_shop_stock_level_adjustments"."created_at" > current_date - interval \'90 days\' AND "adjustment" < 0 AND order_item_id IS NOT NULL THEN 1 ELSE 0 END) as order_picking_90_days, 

        SUM(CASE WHEN "spina_shop_stock_level_adjustments"."created_at" > current_date - interval \'365 days\' AND "adjustment" < 0 AND order_item_id IS NOT NULL THEN 1 ELSE 0 END) as order_picking_365_days, 

        SUM(CASE WHEN "spina_shop_stock_level_adjustments"."created_at" > current_date - interval \'42 days\' - interval \'1 day\' * (CASE WHEN lead_time IS NULL THEN 1 ELSE lead_time END) AND order_item_id IS NOT NULL THEN "adjustment" ELSE 0 END) * -1 as optimal_stock, 

        stock_level - (SUM(CASE WHEN "spina_shop_stock_level_adjustments"."created_at" > current_date - interval \'42 days\' - interval \'1 day\' * (CASE WHEN lead_time IS NULL THEN 1 ELSE lead_time END) AND order_item_id IS NOT NULL THEN "adjustment" ELSE 0 END) * -1) as stock_difference, 

        stock_level * cost_price AS stock_value, (SELECT COUNT(*) FROM spina_shop_in_stock_reminders WHERE orderable_type = \'Spina::Shop::Product\' AND orderable_id = spina_shop_products.id) as in_stock_reminders_count, 

        (SELECT difference FROM spina_shop_recounts WHERE product_id = spina_shop_products.id ORDER BY created_at DESC LIMIT 1) as recount_difference, 

        (SELECT created_at FROM spina_shop_recounts WHERE product_id = spina_shop_products.id ORDER BY created_at DESC LIMIT 1) as recount_created_at, spina_shop_products.*, 

        CASE WHEN (cost_price > 0 AND SUM(CASE WHEN "spina_shop_stock_level_adjustments"."created_at" > current_date - interval \'365 days\' AND order_item_id IS NOT NULL THEN "adjustment" ELSE 0 END) * -1 > 0) THEN
          ((SUM(CASE WHEN "spina_shop_stock_level_adjustments"."created_at" < current_date - interval \'365 days\' THEN "adjustment" ELSE 0 END) + stock_level) / 2 * cost_price) * 365 / (cost_price * (SUM(CASE WHEN "spina_shop_stock_level_adjustments"."created_at" > current_date - interval \'365 days\' AND order_item_id IS NOT NULL THEN "adjustment" ELSE 0 END) * -1)) 
        ELSE 0 END as lead_time'
      ).purchasable
       .where(stock_enabled: true, archived: false)
       .left_outer_joins(:stock_level_adjustments)
       .joins("LEFT JOIN spina_shop_suppliers ON spina_shop_products.supplier_id = spina_shop_suppliers.id")
       .group('"spina_shop_products"."id"') }
    end

    def in_stock?
      return true unless stock_enabled?
      stock_level > 0
    end
    
    def stock_value
      stock_level * (cost_price || 0)
    end
    
    def dimensions
      "#{length}x#{width}x#{height} (LBH)"
    end
    
    def volume
      return 0 unless length && width && height
      (length * width * height / 1000.to_f).round(2)
    end

    def cache_stock_level
      update_columns(
        stock_level: stock_level_adjustments.sum(:adjustment), 
        sales_count: stock_level_adjustments.sales.sum(:adjustment) * -1,
        expiration_date: can_expire? ? earliest_expiration_date : nil
      )
      touch
    end

    def expiration_month
      expiration_date.try(:month)
    end

    def expiration_year
      expiration_date.try(:year)
    end
    
    # All additions
    def active_adjustments
      offset = 0
      sum = 0
      adjustment = stock_level_adjustments.ordered.additions.offset(offset).first
      adjustments = [adjustment]
      while sum < stock_level && adjustment.present? do
        adjustment = stock_level_adjustments.ordered.additions.offset(offset).first
        adjustments << adjustment
        offset = offset.next
        sum = sum + adjustment&.adjustment.to_i
      end
      adjustments
    end
    
    # Expiration dates that are in currently available as stock
    def active_expiration_dates
      active_adjustments.map do |adjustment|
        if adjustment&.expiration_year.present?
          Date.new.change(day: 1, month: adjustment.expiration_month || 1, year: adjustment.expiration_year)
        end
      end.compact.uniq.sort
    end
    
    def earliest_expiration_date
      adjustment = active_adjustments.last
      return nil unless adjustment&.expiration_year.present?
      Date.new.change(day: 1, month: adjustment.expiration_month || 1, year: adjustment.expiration_year)
    end

    private

      def create_initial_stock_level_adjustment
        ChangeStockLevel.new(self, adjustment: initial_stock_level).save
      end
  end
end