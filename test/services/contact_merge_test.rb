require "test_helper"

class ContactMergeTest < ActiveSupport::TestCase
  setup do
    @project = keila_projects(:alpha)
    @leading = @project.contacts.create!(email: "info@kfh-dialyse.de", first_name: "KfH", status: "active",
                                         data: { "Tags" => [ "clinic" ], "City" => "Heidelberg" })
    @other = @project.contacts.create!(email: "info@kfh-dialysse.de", first_name: "Kuratorium", last_name: "Heimdialyse",
                                       external_id: "kfh-1", status: "unreachable",
                                       data: { "Tags" => [ "clinic", "board" ], "City" => "Mannheim", "Phone" => "123" })
  end

  test "the leading contact keeps its values and gets the other's blanks filled in and tags added" do
    ContactMerge.new(@leading, @other).apply!
    @leading.reload

    assert_equal "info@kfh-dialyse.de", @leading.email
    assert_equal "KfH", @leading.first_name
    assert_equal "Heimdialyse", @leading.last_name
    assert_equal "kfh-1", @leading.external_id
    assert_equal "active", @leading.status
    assert_equal %w[clinic board], @leading.tags
    assert_equal "Heidelberg", @leading.custom_field("City")
    assert_equal "123", @leading.custom_field("Phone")
    assert_not Contact.exists?(@other.id)
  end

  test "an unsubscribed status on the other contact is kept" do
    @other.update!(status: "unsubscribed")

    merge = ContactMerge.new(@leading, @other)
    assert_equal [ "unsubscribed", :other ], merge.rows.find { |row| row.label == "Status" }.then { |row| [ row.result, row.source ] }

    merge.apply!
    assert_equal "unsubscribed", @leading.reload.status
  end

  test "rows say where each value comes from" do
    sources = ContactMerge.new(@leading, @other).rows.to_h { |row| [ row.label, row.source ] }

    assert_equal :leading, sources["Email"]
    assert_equal :leading, sources["First name"]
    assert_equal :other, sources["Last name"]
    assert_equal :both, sources["Tags"]
    assert_equal :leading, sources["City"]
    assert_equal :other, sources["Phone"]
  end

  test "deleting a synced contact by merging leaves a tombstone for the next sync" do
    @other.update!(keila_id: "c_other", sync_snapshot: @other.sync_state)

    ContactMerge.new(@leading, @other).apply!

    assert @project.contact_deletions.exists?(keila_id: "c_other")
  end

  test "the next sync deletes the merged-in contact in Keila and updates the leading one" do
    keila = FakeKeila.new
    sync = -> { KeilaSync::Executor.run(KeilaSync::Plan.build(@project.reload, remote_contacts: keila.all_contacts), client: keila) }
    sync.call
    other_keila_id = @other.reload.keila_id

    ContactMerge.new(@leading.reload, @other).apply!
    sync.call

    assert_not keila.contacts.key?(other_keila_id)
    remote = keila.contacts.fetch(@leading.reload.keila_id)
    assert_equal "Heimdialyse", remote["last_name"]
    assert_equal "kfh-1", remote["external_id"]
    assert KeilaSync::Plan.build(@project.reload, remote_contacts: keila.all_contacts).in_sync?
  end

  test "refuses contacts of different projects" do
    stranger = keila_projects(:beta).contacts.create!(email: "x@example.com")

    assert_raises(ArgumentError) { ContactMerge.new(@leading, stranger) }
  end
end
