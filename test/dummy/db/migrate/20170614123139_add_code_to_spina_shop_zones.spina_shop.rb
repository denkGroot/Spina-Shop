# This migration comes from spina_shop (originally 6)
class AddCodeToSpinaShopZones < ActiveRecord::Migration[5.1]
  def change
    add_column :spina_shop_zones, :code, :string
  end
end
