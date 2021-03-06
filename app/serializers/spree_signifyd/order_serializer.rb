require 'active_model/serializer'

module SpreeSignifyd
  class OrderSerializer < ActiveModel::Serializer
    self.root = false

    attributes :purchase, :recipient, :card
    has_one :user, serializer: SpreeSignifyd::UserSerializer, root: "userAccount"

    def purchase
      build_purchase_information.tap do |purchase_info|
        if paid_by_paypal?
          purchase_info["paymentGateway"] = "paypal_account"
        end
      end
    end

    def recipient
      recipient = SpreeSignifyd::DeliveryAddressSerializer.new(object.ship_address).serializable_object
      recipient[:confirmationEmail] = object.email
      recipient[:fullName] = object.ship_address.full_name
      recipient
    end

    def card
      payment_source = latest_payment.try(:source)
      card = {}

      if payment_source.present? && payment_source.instance_of?(Spree::CreditCard)
        card = CreditCardSerializer.new(payment_source).serializable_object
        card.merge!(SpreeSignifyd::BillingAddressSerializer.new(object.bill_address).serializable_object)
      end

      card
    end

    private

    def paid_by_paypal?
      latest_payment.try!(:source) && latest_payment.source.cc_type == "paypal"
    end

    def build_purchase_information
      {
        'browserIpAddress' => object.last_ip_address,
        'orderId' => object.number,
        'createdAt' => object.completed_at.utc.iso8601,
        'currency' => object.currency,
        'totalPrice' => object.total,
        'products' => products,
        'avsResponseCode' => latest_payment.try!(:avs_response),
        'cvvResponseCode' => latest_payment.try!(:cvv_response_code)
      }
    end

    def products
      order_products = []

      object.line_items.each do |li|
        serialized_line_item = SpreeSignifyd::LineItemSerializer.new(li).serializable_object
        order_products << serialized_line_item
      end

      order_products
    end

    def latest_payment
      object.payments.order(:created_at, :id).last
    end
  end
end
