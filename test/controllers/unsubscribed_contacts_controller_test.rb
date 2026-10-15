require "test_helper"

class UnsubscribedContactsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    @project = users(:one).current_keila_project
    @old = @project.contacts.create!(email: "old@example.com", status: "unsubscribed", status_changed_at: 40.days.ago)
    @recent = @project.contacts.create!(email: "recent@example.com", status: "unsubscribed")
  end

  test "the contacts page points out contacts unsubscribed for long" do
    get contacts_path

    assert_select "a[href=?]", unsubscribed_contacts_path, text: "Review & delete"
    assert_match(/been unsubscribed for\s+30 days or longer/, response.body)
  end

  test "no notice while nobody has been unsubscribed for long" do
    @old.destroy!

    get contacts_path

    assert_select "a", text: "Review & delete", count: 0
  end

  test "index lists unsubscribed contacts, those due for deletion preselected" do
    get unsubscribed_contacts_path

    assert_response :success
    assert_select "input[type=checkbox][value=?][checked]", @old.id.to_s
    assert_select "input[type=checkbox][value=?]:not([checked])", @recent.id.to_s
    assert_no_match "alice@example.com", response.body
  end

  test "purge deletes the selected unsubscribed contacts, leaving tombstones for synced ones" do
    @old.update!(keila_id: "nc_9")

    post purge_unsubscribed_contacts_path, params: { contact_ids: [ @old.id ] }

    assert_redirected_to unsubscribed_contacts_path
    assert_not Contact.exists?(@old.id)
    assert Contact.exists?(@recent.id)
    assert @project.contact_deletions.exists?(keila_id: "nc_9")
  end

  test "purge leaves contacts alone that aren't unsubscribed (anymore)" do
    active = contacts(:one)

    post purge_unsubscribed_contacts_path, params: { contact_ids: [ active.id ] }

    assert Contact.exists?(active.id)
    assert_equal "Select at least one contact first.", flash[:alert]
  end

  test "purge ignores another project's contacts" do
    stranger = keila_projects(:beta).contacts.create!(email: "x@example.com", status: "unsubscribed", status_changed_at: 1.year.ago)

    post purge_unsubscribed_contacts_path, params: { contact_ids: [ stranger.id, @old.id ] }

    assert Contact.exists?(stranger.id)
    assert_not Contact.exists?(@old.id)
  end
end
