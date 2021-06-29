json.(@product, :id, :ean, :stock_level, :location, :expiration_date)
json.full_name @product.full_name
json.name @product.name
json.variant_name @product.variant_name
json.description @product.description
json.properties @product.properties
json.locations @product.product_locations do |location|
  json.name location.location.name
  json.location_code location.location_code
end