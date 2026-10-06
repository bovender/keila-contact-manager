require "test_helper"

class MergesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    @alice = contacts(:one)
    @bob = contacts(:two)
  end

  test "new previews merging into the first contact unless another one is chosen to lead" do
    get new_merge_path(contact_ids: [ @alice.id, @bob.id ])
    assert_response :success
    assert_match "Merge into #{@alice.email}", response.body

    get new_merge_path(contact_ids: [ @alice.id, @bob.id ], leading_id: @bob.id)
    assert_match "Merge into #{@bob.email}", response.body
  end

  test "create merges into the leading contact and deletes the other" do
    post merge_path, params: { contact_ids: [ @alice.id, @bob.id ], leading_id: @bob.id }

    assert_redirected_to contact_path(@bob)
    assert_not Contact.exists?(@alice.id)
    assert_equal "Acme", @bob.reload.custom_field("Company")
    assert_equal %w[newsletter vip], @bob.tags.sort
  end

  test "create returns to the duplicates page when coming from there" do
    post merge_path, params: { contact_ids: [ @alice.id, @bob.id ], return_to: "duplicates" }

    assert_redirected_to duplicates_path
  end

  test "needs exactly two contacts of the active project" do
    get new_merge_path(contact_ids: [ @alice.id ])
    assert_redirected_to contacts_path

    stranger = keila_projects(:beta).contacts.create!(email: "x@example.com")
    post merge_path, params: { contact_ids: [ @alice.id, stranger.id ] }
    assert_response :not_found
    assert Contact.exists?(@alice.id)
  end

  test "merge selected on the contacts page needs exactly two contacts" do
    post bulk_merge_contacts_path, params: { contact_ids: [ @alice.id, @bob.id ] }
    assert_redirected_to new_merge_path(contact_ids: [ @alice.id.to_s, @bob.id.to_s ])

    post bulk_merge_contacts_path, params: { contact_ids: [ @alice.id ] }
    assert_redirected_to contacts_path
    assert_equal "Select exactly two contacts to merge.", flash[:alert]
  end
end
