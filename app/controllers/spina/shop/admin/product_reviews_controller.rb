module Spina::Shop
  module Admin
    class ProductReviewsController < AdminController
      layout 'spina/shop/admin/reviews'
      
      def index
        @product_reviews = ProductReview.sorted.page(params[:page]).per(25)
        add_breadcrumb ProductReview.model_name.human(count: :other)
      end

      def delete_multiple
        ProductReview.where(id: params[:product_review_ids]).destroy_all
        redirect_to spina.shop_admin_product_reviews_path
      end

    end
  end
end