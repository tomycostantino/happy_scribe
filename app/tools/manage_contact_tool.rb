class ManageContactTool < RubyLLM::Tool
  description "Creates or updates a contact in the user's address book. " \
              "Use when you learn someone's email address to save it for future use."

  param :name, type: :string, desc: "Contact's full name"
  param :email, type: :string, desc: "Contact's email address"
  param :notes, type: :string, desc: "Optional notes about the contact (role, team, etc.)", required: false

  def initialize(user)
    @user = user
  end

  def execute(name:, email:, notes: nil)
    contact = @user.contacts.find_or_initialize_by(email: email.strip.downcase)
    updating = contact.persisted?

    contact.name = name
    contact.notes = notes if notes
    contact.save!

    if updating
      "Updated contact: #{contact.name} <#{contact.email}>"
    else
      "Saved contact: #{contact.name} <#{contact.email}>"
    end
  rescue ActiveRecord::RecordInvalid => e
    "Failed to save contact: #{e.message}"
  end
end
