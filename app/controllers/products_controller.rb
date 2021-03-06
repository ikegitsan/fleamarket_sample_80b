class ProductsController < ApplicationController
  before_action :move_to_index, except: [:index, :show, :search]
  before_action :set_product, only: [:show, :destroy, :edit, :update, :buy, :pay]

  require "payjp"

  def index
    @products = Product.includes(:images).order('created_at DESC')
  end

  def show
    @grandchild = @product.category
    @child = @grandchild.parent
    @parent = @child.parent
  end

  def new
    @product = Product.new
    @product.images.new
  end

  def create
    @product = Product.new(product_params)
    if @product.save
      redirect_to root_path, notice: '商品が出品されました'
    else
      flash.now[:alert] = '商品情報に未入力があります'
      render :new
    end
  end

  def destroy
    if @product.destroy
      redirect_to root_path, notice: '商品が削除されました'
    else
      flash.now[:alert] = '商品削除に失敗しました'
    end
  end

  def edit
    @product.images.new
  end

  def update
    if @product.update(product_params)
      redirect_to root_path, notice: '商品が更新されました'
    else
      flash.now[:alert] = '商品情報に未入力があります'
      render :edit
    end
  end

  def search
    @search = Product.ransack(params[:q]) 
    @search_products = @search.result
  end

  def get_category_children
    respond_to do |format| 
      format.html
      format.json do
        @category_children = Category.find("#{params[:parent_id]}").children
      end
    end
  end
  
  def get_category_grandchildren
    respond_to do |format| 
      format.html
      format.json do
        @category_grandchildren = Category.find("#{params[:child_id]}").children
      end
    end
  end
  
  def buy
    # 商品ごとに複数枚写真を登録できるので、一応全部持ってきておきます。
    # @images = @product.images.all
    @user = current_user
    # まずはログインしているか確認
    if user_signed_in?
      # クレジットカードが登録されているか確認
      @card = CreditCard.find_by(user_id: current_user.id)
      if @card.blank?

      else
        # 前前回credentials.yml.encに記載したAPI秘密鍵を呼び出します。
        Payjp.api_key = Rails.application.credentials.dig(:payjp, :PAYJP_SECRET_KEY)
        # ログインユーザーのクレジットカード情報からPay.jpに登録されているカスタマー情報を引き出す
        customer = Payjp::Customer.retrieve(@card.customer_id)
        # カスタマー情報からカードの情報を引き出す
        @customer_card = customer.cards.retrieve(@card.card_id)

        #  viewの記述を簡略化
        ## 有効期限'月'を定義
        @exp_month = @customer_card.exp_month.to_s
        ## 有効期限'年'を定義
        @exp_year = @customer_card.exp_year.to_s.slice(2,3)
      end
    else
      # ログインしていなければ、商品の購入ができずに、ログイン画面に移動します。
      redirect_to root_path, alert: "ログインしてください"
    end
  end

  def pay
    # 購入テーブル登録ずみ商品は２重で購入されないようにする
    # (２重で決済されることを防ぐ)
    
    # if @product.judgment.present?
    if @product.judgment == "売却済み"
      redirect_to product_path(@product.id), alert: "売り切れています。"
    else
      # 同時に2人が同時に購入し、二重で購入処理がされることを防ぐための記述
      @product.with_lock do
        if current_user.credit_card.present?
          # ログインユーザーがクレジットカード登録済みの場合の処理
          # ログインユーザーのクレジットカード情報を引っ張ってきます。
          @card = CreditCard.find_by(user_id: current_user.id)
          # 前前前回credentials.yml.encに記載したAPI秘密鍵を呼び出します。
          Payjp.api_key = Rails.application.credentials.dig(:payjp, :PAYJP_SECRET_KEY)
          #登録したカードでの、クレジットカード決済処理
          charge = Payjp::Charge.create(
          # 商品(product)の値段を引っ張ってきて決済金額(amount)に入れる
          amount: @product.price,
          customer: Payjp::Customer.retrieve(@card.customer_id),
          currency: 'jpy'
          )
        else
          # ログインユーザーがクレジットカード登録されていない場合(Checkout機能による処理を行います)
          # APIの「Checkout」ライブラリによる決済処理の記述
          Payjp.api_key = Rails.application.credentials.dig(:payjp, :PAYJP_SECRET_KEY)
          charge = Payjp::Charge.create(
          amount: @product.price,
          card: params['payjp-token'], # フォームを送信すると作成・送信されてくるトークン
          currency: 'jpy'
          )
        end

      #productテーブルに登録処理(judgmentカラムに売却済みを追加する)
      @product.update(judgment: "売却済み", buyer_id: current_user.id)
      # @purchase = Product.create(judgment: 1)
      end
    end
  end

  private

  def product_params
    params.require(:product).permit(:name, :price, :cost, :description, :prefecture_id, :delivery_id, :brand, :size_id, :category_id, :status_id, images_attributes: [:url, :_destroy, :id]).merge(user_id: current_user.id, judgment: "出品中")
  end

  def move_to_index
    unless user_signed_in?
      redirect_to action: :index
    end
  end

  def set_product
    @product = Product.find(params[:id])
  end
end

