require "test_helper"

class KeilaProjectTest < ActiveSupport::TestCase
  test "requires a unique, present name" do
    project = KeilaProject.new
    assert_not project.valid?
    assert_includes project.errors[:name], "can't be blank"

    project = KeilaProject.new(name: keila_projects(:alpha).name)
    assert_not project.valid?
    assert_includes project.errors[:name], "has already been taken"
  end

  test "requires an API key" do
    project = KeilaProject.new(name: "Gamma")
    assert_not project.valid?
    assert_includes project.errors[:keila_api_key], "can't be blank"
  end

  test "configured_for_sync? requires the instance URL and an API key" do
    project = keila_projects(:alpha)
    assert project.configured_for_sync?

    with_keila_url(nil) { assert_not project.configured_for_sync? }
  end

  test "keila_api_key is stored encrypted" do
    project = KeilaProject.create!(name: "Encrypted test", keila_api_key: "secret")
    raw = ActiveRecord::Base.connection.select_value(
      "SELECT keila_api_key FROM keila_projects WHERE id = #{project.id}"
    )
    assert_not_equal "secret", raw
    assert_equal "secret", project.reload.keila_api_key
  end

  test "destroying removes the local contacts and fields without leaving tombstones" do
    project = keila_projects(:alpha)
    contacts(:one).update!(keila_id: "nc_1")

    assert_no_difference "ContactDeletion.count" do
      assert project.destroy
    end
    assert_equal 0, Contact.where(keila_project_id: project.id).count
    assert_equal 0, CustomFieldDefinition.unscoped.where(keila_project_id: project.id).count
  end
end
