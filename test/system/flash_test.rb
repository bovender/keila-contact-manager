require "application_system_test_case"

class FlashTest < ApplicationSystemTestCase
  test "a notice floats over the page until dismissed" do
    sign_in_via_ui(users(:one))
    visit new_contact_path
    execute_script(%(document.getElementById("contact_email").value = "new@example.com"))
    js_click(:button, "Create Contact")

    assert_selector "#notice", text: "Contact created."
    assert_equal "fixed", evaluate_script(%(getComputedStyle(document.getElementById("notice").parentElement).position))

    js_click("#notice button")
    assert_no_selector "#notice"
  end
end
