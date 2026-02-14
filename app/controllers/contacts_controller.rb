class ContactsController < ApplicationController
  before_action :set_contact, only: %i[show edit update destroy]

  def index
    @contacts = Current.user.contacts.order(:name)
    @contacts = @contacts.search_by_name(params[:query]) if params[:query].present?
  end

  def show
  end

  def new
    @contact = Contact.new
  end

  def create
    @contact = Current.user.contacts.build(contact_params)

    if @contact.save
      redirect_to contacts_url, notice: "Contact created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @contact.update(contact_params)
      redirect_to contacts_url, notice: "Contact updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @contact.destroy!
    redirect_to contacts_url, notice: "Contact deleted."
  end

  private

  def set_contact
    @contact = Current.user.contacts.find(params[:id])
  end

  def contact_params
    params.require(:contact).permit(:name, :email, :notes)
  end
end
