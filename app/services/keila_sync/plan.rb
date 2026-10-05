module KeilaSync
  # Compares a project's local contacts (and tombstones of deleted ones)
  # with every contact in its Keila project, and works out one Item per
  # contact that needs anything done. Nothing is changed here; the plan is
  # shown on the sync screen, and KeilaSync::Executor carries it out.
  #
  # Local and Keila contacts are paired by Keila's contact id once they've
  # been synced. Before that (or if a contact was re-created in Keila),
  # they're matched like a CSV import: this app's uuid embedded in Data,
  # then External_id, then email.
  #
  # Each paired field is compared three ways, against the snapshot from
  # the last sync: changed on one side only means that side wins; changed
  # on both sides (to different values) is a conflict for the user to
  # decide. Without a snapshot (never synced before), a value present on
  # only one side is taken over, and differing values are conflicts.
  class Plan
    # kind:
    #   :update                 paired; `fields` says what goes where
    #   :link                   paired and already identical; just remember the pairing
    #   :create_local           new in Keila
    #   :create_remote          new here
    #   :delete_local           deleted in Keila, unchanged here since
    #   :delete_remote          deleted here, unchanged in Keila since
    #   :drop_tombstone         deleted on both sides
    #   :remote_deleted_conflict  deleted in Keila, but changed here since
    #   :local_deleted_conflict   deleted here, but changed in Keila since
    class Item
      attr_reader :kind, :contact, :remote, :deletion, :fields

      def initialize(kind, contact: nil, remote: nil, deletion: nil, fields: {})
        @kind = kind
        @contact = contact
        @remote = remote
        @deletion = deletion
        @fields = fields
      end

      def email
        contact&.email || remote&.dig("email") || deletion&.email
      end

      def keila_id
        remote&.dig("id") || contact&.keila_id || deletion&.keila_id
      end

      def pull_fields
        fields.select { |_, f| f[:action] == :pull }.keys
      end

      def push_fields
        fields.select { |_, f| f[:action] == :push }.keys
      end

      # Field conflicts of an :update, or the single keep-or-delete
      # decision of a deletion conflict, as { token => field }.
      def conflicts
        case kind
        when :update
          fields.select { |_, f| f[:action] == :conflict }.keys.index_by { |field| KeilaSync.token(contact.uuid, field) }
        when :remote_deleted_conflict
          { KeilaSync.token(contact.uuid, "_existence") => nil }
        when :local_deleted_conflict
          { KeilaSync.token("keila", deletion.keila_id, "_existence") => nil }
        else
          {}
        end
      end

      def deletion?
        %i[delete_local delete_remote remote_deleted_conflict local_deleted_conflict].include?(kind)
      end

      def changes_local?
        %i[create_local delete_local].include?(kind) || (kind == :update && pull_fields.any?)
      end

      def changes_remote?
        %i[create_remote delete_remote].include?(kind) || (kind == :update && push_fields.any?)
      end
    end

    attr_reader :project, :items

    def self.build(project, remote_contacts: KeilaApi.client!(project).all_contacts)
      new(project, remote_contacts)
    end

    def initialize(project, remote_contacts)
      @project = project
      @items = []
      build(remote_contacts)
    end

    def in_sync?
      items.none? { |item| item.changes_local? || item.changes_remote? || item.conflicts.any? }
    end

    def from_keila
      items.select(&:changes_local?)
    end

    def from_here
      items.select(&:changes_remote?)
    end

    def conflicted
      items.select { |item| item.conflicts.any? }
    end

    def conflict_count
      items.sum { |item| item.conflicts.size }
    end

    def deletions?
      items.any?(&:deletion?)
    end

    # What a single click may do without showing the sync screen first:
    # nothing to decide, nothing deleted, and not the very first sync
    # (which pairs up contacts by email & co. and deserves a look).
    def one_click?
      project.synced? && conflict_count.zero? && !deletions?
    end

    def unresolved(resolutions)
      items.flat_map { |item| item.conflicts.keys }.reject { |token| %w[local remote].include?(resolutions[token]) }
    end

    private

    def build(remote_contacts)
      locals = project.contacts.to_a
      deletions = project.contact_deletions.index_by(&:keila_id)
      remote_ids = remote_contacts.map { |r| r["id"] }.to_set

      by_keila_id = locals.select(&:keila_id?).index_by(&:keila_id)
      # Not (or no longer) paired with anything in Keila, so up for matching.
      linkable = locals.reject { |c| c.keila_id? && remote_ids.include?(c.keila_id) }
      @by_uuid = linkable.index_by(&:uuid)
      @by_external_id = linkable.select { |c| c.external_id.present? }.index_by(&:external_id)
      @by_email = linkable.index_by(&:email)
      @matched = Set.new

      remote_contacts.each do |remote|
        if (contact = by_keila_id[remote["id"]])
          @matched << contact.id
          add_pair(contact, remote, contact.sync_snapshot)
        elsif (deletion = deletions[remote["id"]])
          add_deletion(deletion, remote)
        elsif (contact = find_linkable(remote))
          @matched << contact.id
          add_pair(contact, remote, nil)
        else
          @items << Item.new(:create_local, remote: remote)
        end
      end

      locals.each do |contact|
        next if @matched.include?(contact.id)

        if !contact.keila_id?
          @items << Item.new(:create_remote, contact: contact)
        elsif KeilaSync.same_state?(contact.sync_state, contact.sync_snapshot)
          @items << Item.new(:delete_local, contact: contact)
        else
          @items << Item.new(:remote_deleted_conflict, contact: contact)
        end
      end

      deletions.each_value do |deletion|
        @items << Item.new(:drop_tombstone, deletion: deletion) unless remote_ids.include?(deletion.keila_id)
      end
    end

    def find_linkable(remote)
      uid = (remote["data"] || {})[Contact::RESERVED_DATA_KEY]
      candidates = [
        uid.present? && @by_uuid[uid],
        remote["external_id"].present? && @by_external_id[remote["external_id"]],
        @by_email[remote["email"].to_s.strip.downcase]
      ]
      candidates.find { |c| c && !@matched.include?(c.id) }
    end

    def add_deletion(deletion, remote)
      if KeilaSync.same_state?(KeilaSync.remote_state(remote), deletion.snapshot)
        @items << Item.new(:delete_remote, deletion: deletion, remote: remote)
      else
        @items << Item.new(:local_deleted_conflict, deletion: deletion, remote: remote)
      end
    end

    def add_pair(contact, remote, base)
      local_state = contact.sync_state
      remote_state = KeilaSync.remote_state(remote)

      fields = {}
      KeilaSync.fields_of(local_state, remote_state, base).each do |field|
        local = KeilaSync.value_at(local_state, field)
        theirs = KeilaSync.value_at(remote_state, field)
        next if KeilaSync.same_value?(field, local, theirs)

        fields[field] = { local: local, remote: theirs, action: field_action(field, local, theirs, base) }
      end

      if fields.any?
        @items << Item.new(:update, contact: contact, remote: remote, fields: fields)
      elsif contact.keila_id != remote["id"] || !KeilaSync.same_state?(local_state, base)
        @items << Item.new(:link, contact: contact, remote: remote)
      end
    end

    def field_action(field, local, theirs, base)
      if base
        original = KeilaSync.value_at(base, field)
        return :pull if KeilaSync.same_value?(field, local, original)
        return :push if KeilaSync.same_value?(field, theirs, original)
      else
        return :pull if KeilaSync.normalize(field, local).nil?
        return :push if KeilaSync.normalize(field, theirs).nil?
      end
      :conflict
    end
  end
end
