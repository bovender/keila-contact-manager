require "test_helper"

class InactiveContactsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    @project = users(:one).current_keila_project
    @old = @project.contacts.create!(email: "old@example.com", status: "unsubscribed", status_changed_at: 40.days.ago)
    @recent = @project.contacts.create!(email: "recent@example.com", status: "unsubscribed")
    @bounced = @project.contacts.create!(email: "bounced@example.com", status: "unreachable", status_changed_at: 40.days.ago)
  end

  test "the contacts page points out contacts inactive for long" do
    get contacts_path

    assert_select "a[href=?]", inactive_contacts_path, text: "Review & delete"
    assert_match(/2 contacts<\/span>\s+have been unsubscribed or unreachable for\s+30 days or longer/, response.body)
  end

  test "no notice while nobody has been inactive for long" do
    @old.destroy!
    @bounced.update!(status: "active")

    get contacts_path

    assert_select "a", text: "Review & delete", count: 0
  end

  test "index lists inactive contacts, those due for deletion preselected" do
    get inactive_contacts_path

    assert_response :success
    assert_select "input[type=checkbox][value=?][checked]", @old.id.to_s
    assert_select "input[type=checkbox][value=?][checked]", @bounced.id.to_s
    assert_select "input[type=checkbox][value=?]:not([checked])", @recent.id.to_s
    assert_no_match "alice@example.com", response.body
  end

  test "purge deletes the selected inactive contacts, leaving tombstones for synced ones" do
    @old.update!(keila_id: "nc_9")

    post purge_inactive_contacts_path, params: { contact_ids: [ @old.id, @bounced.id ] }

    assert_redirected_to inactive_contacts_path
    assert_not Contact.exists?(@old.id)
    assert_not Contact.exists?(@bounced.id)
    assert Contact.exists?(@recent.id)
    assert @project.contact_deletions.exists?(keila_id: "nc_9")
  end

  test "purge leaves contacts alone that aren't inactive (anymore)" do
    active = contacts(:one)

    post purge_inactive_contacts_path, params: { contact_ids: [ active.id ] }

    assert Contact.exists?(active.id)
    assert_equal "Select at least one contact first.", flash[:alert]
  end

  test "purge ignores another project's contacts" do
    stranger = keila_projects(:beta).contacts.create!(email: "x@example.com", status: "unsubscribed", status_changed_at: 1.year.ago)

    post purge_inactive_contacts_path, params: { contact_ids: [ stranger.id, @old.id ] }

    assert Contact.exists?(stranger.id)
    assert_not Contact.exists?(@old.id)
  end
end
