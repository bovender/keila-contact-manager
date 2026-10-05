require "test_helper"

# Plan and Executor together, against FakeKeila: most of what matters here
# is that both sides end up identical and the next plan is empty.
class KeilaSyncTest < ActiveSupport::TestCase
  setup do
    @project = keila_projects(:alpha)
    @keila = FakeKeila.new
    @alice = contacts(:one)
    @bob = contacts(:two)
  end

  def plan
    KeilaSync::Plan.build(@project.reload, remote_contacts: @keila.all_contacts)
  end

  def sync!(resolutions = {})
    KeilaSync::Executor.run(plan, resolutions: resolutions, client: @keila)
  end

  # Both fixture contacts synced once, with nothing in Keila beforehand.
  def synced!
    sync!
    @alice.reload
    @bob.reload
    @calls_before = @keila.calls.size
  end

  def remote(contact)
    @keila.contacts.fetch(contact.reload.keila_id)
  end

  def item_for(plan, email)
    plan.items.find { |item| item.email == email }
  end

  # -- first sync -------------------------------------------------------

  test "first sync pushes local-only contacts and pulls Keila-only ones" do
    @keila.add(email: "carol@example.com", first_name: "Carol", data: { "City" => "Mainz" })

    result = sync!

    assert_equal 1, result.pulled
    assert_equal 2, result.pushed
    carol = @project.contacts.find_by!(email: "carol@example.com")
    assert_equal "Mainz", carol.custom_field("City")
    assert_equal "active", carol.status
    assert_equal "Acme", remote(@alice)["data"]["Company"]
    assert_equal @alice.uuid, remote(@alice)["data"][Contact::RESERVED_DATA_KEY]
    assert_equal [ "vip", "newsletter" ], remote(@alice)["data"]["Tags"]
    assert plan.in_sync?
    assert @project.reload.synced?
  end

  test "first sync registers custom fields that only exist in Keila" do
    @keila.add(email: "carol@example.com", data: { "City" => "Mainz" })

    sync!

    assert @project.custom_field_definitions.exists?(key: "City")
  end

  test "first sync pairs existing contacts by email and merges fields present on one side" do
    @keila.add(email: "Alice@Example.com", first_name: "Alice", last_name: nil, data: { "City" => "Mainz" })

    item = item_for(plan, "alice@example.com")
    assert_equal :update, item.kind
    assert_equal %w[data:City], item.pull_fields
    assert_includes item.push_fields, "last_name"
    assert_empty item.conflicts

    sync!
    assert_equal "Mainz", @alice.reload.custom_field("City")
    assert_equal "Anderson", remote(@alice)["last_name"]
    assert_equal 2, @keila.contacts.size
    assert plan.in_sync?
  end

  test "first sync turns differing values on both sides into conflicts" do
    @keila.add(email: "alice@example.com", first_name: "Alicia", data: { "Company" => "Initech" })

    item = item_for(plan, "alice@example.com")
    assert_equal %w[first_name data:Company], item.conflicts.values
    assert_not plan.one_click?
    assert_raises(KeilaSync::UnresolvedConflictsError) { sync! }

    tokens = item.conflicts.invert
    sync!(tokens["first_name"] => "remote", tokens["data:Company"] => "local")

    assert_equal "Alicia", @alice.reload.first_name
    assert_equal "Alicia", remote(@alice)["first_name"]
    assert_equal "Acme", remote(@alice)["data"]["Company"]
    assert plan.in_sync?
  end

  test "first sync pairs by the embedded uid even when the email changed in Keila" do
    @keila.add(email: "alice.new@example.com", data: { Contact::RESERVED_DATA_KEY => @alice.uuid, "Company" => "Acme" })

    item = item_for(plan, "alice@example.com")
    assert_equal %w[email], item.conflicts.values
    sync!(item.conflicts.keys.index_with { "remote" })

    assert_equal "alice.new@example.com", @alice.reload.email
    assert_equal 2, @keila.contacts.size
  end

  test "first sync is never one-click" do
    assert_not plan.one_click?
  end

  # -- later syncs ------------------------------------------------------

  test "after a sync, nothing is due and nothing is written" do
    synced!

    assert plan.in_sync?
    sync!
    assert_empty @keila.calls.drop(@calls_before).reject { |call| call.first == :all_contacts }
  end

  test "a change made in Keila is pulled" do
    synced!
    @keila.edit(@alice.keila_id, "first_name" => "Ally", "data" => remote(@alice)["data"].merge("City" => "Mainz"))

    current = plan
    assert_equal [ @alice.email ], current.from_keila.map(&:email)
    assert_empty current.from_here
    assert current.one_click?

    sync!
    assert_equal "Ally", @alice.reload.first_name
    assert_equal "Mainz", @alice.custom_field("City")
    assert_empty @keila.calls.drop(@calls_before).reject { |call| call.first == :all_contacts }
  end

  test "a change made here is pushed, merging only the changed data keys" do
    synced!
    @alice.update!(first_name: "Ally", tags: %w[vip])

    assert_equal [ @alice.email ], plan.from_here.map(&:email)
    sync!

    assert_equal "Ally", remote(@alice)["first_name"]
    assert_equal %w[vip], remote(@alice)["data"]["Tags"]
    data_write = @keila.writes.find { |call| call.first == :update_contact_data }
    assert_equal({ "Tags" => %w[vip] }, data_write.last)
    assert plan.in_sync?
  end

  test "clearing a field here clears it in Keila" do
    synced!
    @alice.update!(last_name: "")
    @alice.set_custom_field("Company", nil)
    @alice.save!

    sync!

    assert_nil remote(@alice)["last_name"]
    assert_not remote(@alice)["data"].key?("Company")
    assert_equal @alice.uuid, remote(@alice)["data"][Contact::RESERVED_DATA_KEY]
    assert plan.in_sync?
  end

  test "changes to different fields on both sides merge without a conflict" do
    synced!
    @alice.update!(first_name: "Ally")
    @keila.edit(@alice.keila_id, "last_name" => "Smith")

    assert_empty plan.conflicted
    sync!

    assert_equal [ "Ally", "Smith" ], [ @alice.reload.first_name, @alice.last_name ]
    assert_equal [ "Ally", "Smith" ], remote(@alice).values_at("first_name", "last_name")
  end

  test "the same field changed differently on both sides is a conflict" do
    synced!
    @alice.update!(first_name: "Ally")
    @keila.edit(@alice.keila_id, "first_name" => "Alicia")

    current = plan
    assert_equal 1, current.conflict_count
    assert_not current.one_click?

    sync!(item_for(current, @alice.email).conflicts.keys.index_with { "local" })
    assert_equal "Ally", remote(@alice)["first_name"]
    assert plan.in_sync?
  end

  test "the same change on both sides is no conflict at all" do
    synced!
    @alice.update!(first_name: "Ally")
    @keila.edit(@alice.keila_id, "first_name" => "Ally")

    assert plan.in_sync?
  end

  test "tag order and email case don't count as changes" do
    synced!
    @keila.edit(@alice.keila_id, "email" => "ALICE@example.com",
                                 "data" => remote(@alice)["data"].merge("Tags" => %w[newsletter vip]))

    assert plan.in_sync?
  end

  # -- deletions --------------------------------------------------------

  test "a contact deleted in Keila is deleted here, after review" do
    synced!
    @keila.contacts.delete(@bob.keila_id)

    current = plan
    assert_equal :delete_local, item_for(current, @bob.email).kind
    assert_not current.one_click?

    assert_no_difference "ContactDeletion.count" do
      sync!
    end
    assert_not Contact.exists?(@bob.id)
    assert plan.in_sync?
  end

  test "a contact deleted in Keila but changed here is a keep-or-delete decision" do
    synced!
    @keila.contacts.delete(@bob.keila_id)
    @bob.update!(first_name: "Robert")

    item = item_for(plan, @bob.email)
    assert_equal :remote_deleted_conflict, item.kind

    sync!(item.conflicts.keys.first => "local")
    assert_equal "Robert", remote(@bob)["first_name"]
    assert plan.in_sync?
  end

  test "a contact deleted here is deleted in Keila" do
    synced!
    keila_id = @bob.keila_id
    @bob.destroy

    assert_equal :delete_remote, plan.items.sole.kind
    result = sync!

    assert_equal 1, result.deleted_in_keila
    assert_not @keila.contacts.key?(keila_id)
    assert_equal 0, @project.contact_deletions.count
    assert plan.in_sync?
  end

  test "a contact deleted here but changed in Keila can be restored" do
    synced!
    keila_id = @bob.keila_id
    @bob.destroy
    @keila.edit(keila_id, "first_name" => "Robert")

    item = plan.items.sole
    assert_equal :local_deleted_conflict, item.kind

    sync!(item.conflicts.keys.first => "remote")
    assert_equal "Robert", @project.contacts.find_by!(keila_id: keila_id).first_name
    assert_equal 0, @project.contact_deletions.count
    assert plan.in_sync?
  end

  test "a contact deleted on both sides just drops its tombstone" do
    synced!
    keila_id = @bob.keila_id
    @bob.destroy
    @keila.contacts.delete(keila_id)

    assert plan.in_sync?
    sync!
    assert_equal 0, @project.contact_deletions.count
  end

  test "a contact re-created in Keila under a new id is paired up again by email" do
    synced!
    old_id = @bob.keila_id
    @keila.contacts.delete(old_id)
    new_id = @keila.add(email: @bob.email, first_name: "Bob", last_name: "Brown", external_id: "ext-2", data: { "Tags" => %w[newsletter] })

    assert_equal :link, item_for(plan, @bob.email).kind
    sync!
    assert_equal new_id, @bob.reload.keila_id
    assert plan.in_sync?
  end

  # -- robustness -------------------------------------------------------

  test "a contact Keila refuses doesn't stop the others" do
    @alice.update_column(:status, "bogus")
    def @keila.create_contact(attrs)
      raise KeilaApi::ResponseError.new(400, "invalid_enum") if attrs["status"] == "bogus"

      super
    end

    result = sync!

    assert_equal 1, result.pushed
    assert_equal [ "alice@example.com" ], result.errors.map { |e| e[:email] }
    assert @bob.reload.keila_id.present?
  end

  test "projects never see each other's Keila contacts" do
    other = Contact.create!(keila_project: keila_projects(:beta), email: "alice@example.com")
    @keila.add(email: "alice@example.com")

    sync!

    assert_nil other.reload.keila_id
    assert @alice.reload.keila_id.present?
  end
end
