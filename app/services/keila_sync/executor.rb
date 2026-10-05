module KeilaSync
  # Carries out a KeilaSync::Plan. `resolutions` maps each conflict's token
  # (see Plan::Item#conflicts) to "local" (this app's version wins) or
  # "remote" (Keila's version wins); every conflict needs one.
  #
  # Every contact ends up identical on both sides, and that state is
  # stored as its new sync_snapshot. Whenever something was written to
  # Keila, the state Keila answered with is what's stored locally too, so
  # anything Keila sets on its own (e.g. a new contact's status) doesn't
  # look like a change on the next sync.
  #
  # One failing contact doesn't stop the rest; failures are collected in
  # the result.
  class Executor
    Result = Struct.new(:pulled, :pushed, :deleted_here, :deleted_in_keila, :errors) do
      def initialize(pulled: 0, pushed: 0, deleted_here: 0, deleted_in_keila: 0, errors: [])
        super
      end
    end

    # Deletions first, so that a contact deleted on one side and re-created
    # with the same email on the other doesn't run into Keila's (or our)
    # unique email constraint.
    ORDER = %i[drop_tombstone delete_local delete_remote remote_deleted_conflict local_deleted_conflict
               link update create_local create_remote].freeze

    def self.run(plan, resolutions: {}, client: KeilaApi.client!(plan.project))
      new(plan, resolutions, client).run
    end

    def initialize(plan, resolutions, client)
      @plan = plan
      @project = plan.project
      @resolutions = resolutions.to_h.stringify_keys
      @client = client
      @result = Result.new
      @new_data_keys = Set.new
    end

    def run
      unresolved = @plan.unresolved(@resolutions)
      raise UnresolvedConflictsError, "#{unresolved.size} conflict(s) still need a decision" if unresolved.any?

      @plan.items.sort_by { |item| ORDER.index(item.kind) }.each do |item|
        apply(item)
      rescue KeilaApi::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
        @result.errors << { email: item.email, message: e.message }
      end

      @new_data_keys.each { |key| @project.custom_field_definitions.register!(key) }
      @project.update!(last_synced_at: Time.current)
      @result
    end

    private

    def apply(item)
      case item.kind
      when :drop_tombstone then item.deletion.destroy!
      when :delete_local then delete_local(item.contact)
      when :delete_remote then delete_remote(item.deletion)
      when :remote_deleted_conflict
        resolution(item) == "local" ? create_remote(item.contact) : delete_local(item.contact)
      when :local_deleted_conflict
        if resolution(item) == "local"
          delete_remote(item.deletion)
        else
          create_local(item.remote)
          item.deletion.destroy!
        end
      when :link then store(item.contact, item.remote)
      when :update then update(item)
      when :create_local then create_local(item.remote)
      when :create_remote then create_remote(item.contact)
      end
    end

    def resolution(item, field = nil)
      token = field ? item.conflicts.key(field) : item.conflicts.keys.first
      @resolutions[token]
    end

    def delete_local(contact)
      # `delete`, not `destroy`: this mirrors a deletion made in Keila, so
      # it mustn't leave a tombstone asking to delete it there again.
      contact.delete
      @result.deleted_here += 1
    end

    def delete_remote(deletion)
      @client.delete_contact(deletion.keila_id)
      deletion.destroy!
      @result.deleted_in_keila += 1
    end

    def create_local(remote)
      store(@project.contacts.new, remote)
      @result.pulled += 1
    end

    def create_remote(contact)
      attrs = contact.sync_state.slice(*Contact::SYNCED_ATTRIBUTES).compact_blank
      remote = @client.create_contact(attrs.merge("data" => remote_data(contact, contact.data)))
      store(contact, remote)
      @result.pushed += 1
    end

    def update(item)
      contact = item.contact
      remote = item.remote
      target = KeilaSync.with_values(KeilaSync.remote_state(remote), item.fields.to_h { |field, f| [ field, chosen_value(item, field, f) ] })

      pushed = false
      attrs = Contact::SYNCED_ATTRIBUTES.reject { |attr| KeilaSync.same_value?(attr, target[attr], remote[attr]) }
      if attrs.any?
        # Keila rejects null but clears a field given an empty string.
        remote = @client.update_contact(remote["id"], attrs.index_with { |attr| target[attr].presence || "" })
        pushed = true
      end

      remote_data = (remote["data"] || {}).except(Contact::RESERVED_DATA_KEY)
      unless KeilaSync.same_state?({ "data" => remote_data }, { "data" => target["data"] }) &&
             (remote["data"] || {})[Contact::RESERVED_DATA_KEY] == contact.uuid
        remote = write_data(contact, remote, target["data"])
        pushed = true
      end

      store(contact, remote)
      @result.pushed += 1 if pushed
      @result.pulled += 1 if item.pull_fields.any? || item.conflicts.values.any? { |field| resolution(item, field) == "remote" }
    end

    def chosen_value(item, field, f)
      case f[:action]
      when :pull then f[:remote]
      when :push then f[:local]
      when :conflict then resolution(item, field) == "local" ? f[:local] : f[:remote]
      end
    end

    # A shallow merge of just the changed keys where possible, so a key
    # added in Keila in the meantime (a form submission, another
    # integration) isn't lost; a full replace only when a key has to go.
    def write_data(contact, remote, data)
      current = remote["data"] || {}
      wanted = remote_data(contact, data)

      if (current.keys - wanted.keys).any?
        @client.replace_contact_data(remote["id"], wanted)
      else
        changed = wanted.reject { |key, value| current.key?(key) && current[key] == value }
        @client.update_contact_data(remote["id"], changed)
      end
    end

    def remote_data(contact, data)
      data.merge(Contact::RESERVED_DATA_KEY => contact.uuid)
    end

    # Makes the local contact match Keila's copy and remembers the pairing.
    def store(contact, remote)
      state = KeilaSync.remote_state(remote)
      @new_data_keys.merge(state["data"].keys - contact.data.keys)

      contact.assign_attributes(state.slice(*Contact::SYNCED_ATTRIBUTES))
      contact.data = state["data"]
      contact.keila_id = remote["id"]
      contact.sync_snapshot = state
      contact.save!
    end
  end
end
