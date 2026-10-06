require "test_helper"

class NameCleanupTest < ActiveSupport::TestCase
  setup do
    @project = keila_projects(:alpha)
    @project.custom_field_definitions.register!("first name")
    @project.custom_field_definitions.register!("Last Name")
  end

  def contact(email, first_name: nil, last_name: nil, **data)
    @project.contacts.create!(email:, first_name:, last_name:, data: data.transform_keys { |key| key.to_s.tr("_", " ") })
  end

  test "moves names out of custom fields and clears NA" do
    only_custom = contact("custom@example.com", "first name": "Carla", "Last Name": "Cruz")
    both = contact("both@example.com", first_name: "Bea", last_name: "Berg", "first name": "Bea", "Last Name": "Berg", Company: "Acme")
    missing = contact("missing@example.com", first_name: "NA", last_name: "NA", "first name": "NA")

    result = NameCleanup.run(@project, apply: true)

    assert_equal [ "Carla", "Cruz", {} ], only_custom.reload.then { [ it.first_name, it.last_name, it.data ] }
    assert_equal [ "Bea", "Berg", { "Company" => "Acme" } ], both.reload.then { [ it.first_name, it.last_name, it.data ] }
    assert_equal [ nil, nil, {} ], missing.reload.then { [ it.first_name, it.last_name, it.data ] }
    assert_equal({ "first_name" => 1, "last_name" => 1 }, result.filled)
    assert_equal({ "first_name" => 1, "last_name" => 1 }, result.cleared)
    assert_equal 3, result.contacts_changed
    assert_equal [ "first name", "Last Name" ], result.removed_keys
    assert_not @project.custom_field_definitions.exists?(key: [ "first name", "Last Name" ])
  end

  test "leaves conflicting names alone, and keeps that field's custom field" do
    conflicting = contact("conflict@example.com", first_name: "Anna", last_name: "NA", "first name": "Anne", "Last Name": "Ames")

    result = NameCleanup.run(@project, apply: true)

    conflicting.reload
    assert_equal [ "Anna", "Ames" ], [ conflicting.first_name, conflicting.last_name ]
    assert_equal({ "first name" => "Anne" }, conflicting.data)
    assert_equal 1, result.conflicts.size
    assert_equal [ "first_name", "Anna", { "first name" => "Anne" } ], result.conflicts.first.then { [ it.field, it.built_in, it.custom ] }
    assert_equal [ "Last Name" ], result.removed_keys
    assert @project.custom_field_definitions.exists?(key: "first name")
  end

  test "changes nothing without apply" do
    only_custom = contact("custom@example.com", "first name": "Carla")

    result = NameCleanup.run(@project)

    assert_equal 1, result.contacts_changed
    assert_nil only_custom.reload.first_name
    assert_equal({ "first name" => "Carla" }, only_custom.data)
    assert @project.custom_field_definitions.exists?(key: "first name")
  end

  test "leaves contacts without anything to clean untouched" do
    result = NameCleanup.run(@project, apply: true)

    assert_equal 0, result.contacts_changed
    assert_empty result.conflicts
  end
end
