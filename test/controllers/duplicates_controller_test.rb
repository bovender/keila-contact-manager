require "test_helper"

class DuplicatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    @project = users(:one).current_keila_project
    @a = @project.contacts.create!(email: "info@kfh-dialyse.de")
    @b = @project.contacts.create!(email: "info@kfh-dialysse.de")
  end

  test "index lists possible duplicates with their reason" do
    get duplicates_path

    assert_response :success
    assert_match "info@kfh-dialysse.de", response.body
    assert_match DuplicateFinder::REASONS[:similar_domain], response.body
  end

  test "dismissing a pair stops suggesting it" do
    post dismiss_duplicates_path, params: { contact_ids: [ @b.id, @a.id ] }

    assert_redirected_to duplicates_path
    follow_redirect!
    assert_match "No possible duplicates found.", response.body
  end

  test "dismiss 404s for another project's contact" do
    stranger = keila_projects(:beta).contacts.create!(email: "x@example.com")

    post dismiss_duplicates_path, params: { contact_ids: [ @a.id, stranger.id ] }

    assert_response :not_found
  end

  test "deleting one copy returns to the duplicates page" do
    delete contact_path(@b, return_to: "duplicates")

    assert_redirected_to duplicates_path
    assert_not Contact.exists?(@b.id)
  end

  test "the contact page points out possible duplicates" do
    get contact_path(@a)

    assert_match "Possible duplicates", response.body
    assert_match "info@kfh-dialysse.de", response.body
  end
end
