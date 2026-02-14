class ContactLookupTool < RubyLLM::Tool
  description "Looks up contacts from the user's address book. " \
              "Use to find someone's email address before sending them an email."

  param :name, type: :string, desc: "Name to search for (partial match supported)", required: false
  param :limit, type: :integer, desc: "Maximum results (default 10)", required: false

  def initialize(user)
    @user = user
  end

  def execute(name: nil, limit: 10)
    scope = @user.contacts

    scope = scope.search_by_name(name) if name.present?

    contacts = scope.order(:name).limit(limit)

    return "No contacts found." if contacts.empty?

    contacts.map { |c| format_contact(c) }.join("\n")
  end

  private

  def format_contact(contact)
    line = "#{contact.name} <#{contact.email}>"
    line += " — #{contact.notes}" if contact.notes.present?
    line
  end
end
